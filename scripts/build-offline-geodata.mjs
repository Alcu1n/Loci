#!/usr/bin/env node

import { createHash } from "node:crypto";
import { createReadStream, createWriteStream, existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { pipeline } from "node:stream/promises";
import { createInterface } from "node:readline";
import { spawnSync } from "node:child_process";
import { Readable } from "node:stream";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const output = path.join(root, "Loci", "Resources", "OfflineGeodata");
const work = path.join(root, "build", "offline-geodata");
mkdirSync(output, { recursive: true });
mkdirSync(work, { recursive: true });

const sources = {
  naturalEarth: {
    url: "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/f1890d9f152c896d250a77557a5751a93d494776/geojson/ne_10m_admin_0_countries.geojson",
    sha256: "239eec57ac17f100a11e2536cffc56752c318b50ae765b0918ff7aab4ce8f255",
    version: "5.1.2",
  },
  geoNamesCities: {
    url: "https://download.geonames.org/export/dump/cities1000.zip",
    vendoredPath: "scripts/offline-geodata-sources/cities1000-2026-07-12.zip",
    sha256: "f3a02b4644c48bddded6bf70a579a4b6af8a6ed657a91728eb3873e327c187ba",
    snapshot: "2026-07-12",
  },
  geoNamesAdmin1: {
    url: "https://download.geonames.org/export/dump/admin1CodesASCII.txt",
    vendoredPath: "scripts/offline-geodata-sources/admin1CodesASCII-2026-07-12.txt",
    sha256: "34784457b76b988a669dff7c3e4b104e4902c0875643cff019281ac79dfa2992",
    snapshot: "2026-07-12",
  },
};

async function download(source, filename) {
  const vendored = source.vendoredPath ? path.join(root, source.vendoredPath) : null;
  const destination = vendored && existsSync(vendored) ? vendored : path.join(work, filename);
  if (!existsSync(destination)) {
    const response = await fetch(source.url);
    if (!response.ok || !response.body) throw new Error(`Download failed: ${source.url} (${response.status})`);
    await pipeline(Readable.fromWeb(response.body), createWriteStream(destination));
  }
  const digest = createHash("sha256").update(readFileSync(destination)).digest("hex");
  if (digest !== source.sha256) throw new Error(`Checksum mismatch for ${filename}: ${digest}`);
  return destination;
}

function quantize(value) {
  return Math.round(Number(value) * 10_000) / 10_000;
}

async function buildCountries() {
  const sourcePath = await download(sources.naturalEarth, "countries-10m.geojson");
  const geojson = JSON.parse(readFileSync(sourcePath, "utf8"));
  const countries = geojson.features.map((feature) => {
    const geometry = feature.geometry;
    const polygons = geometry.type === "Polygon" ? [geometry.coordinates] : geometry.coordinates;
    return {
      code: feature.properties.ISO_A2_EH || feature.properties.ISO_A2,
      name: feature.properties.NAME || feature.properties.NAME_LONG || feature.properties.ADMIN,
      continent: feature.properties.CONTINENT,
      polygons: polygons.map((polygon) => polygon.map((ring) => ring.map(([longitude, latitude]) => [quantize(longitude), quantize(latitude)]))),
    };
  });
  writeFileSync(path.join(output, "countries.json"), JSON.stringify(countries));
  return countries.length;
}

async function buildCities() {
  const zipPath = await download(sources.geoNamesCities, "cities1000.zip");
  const adminPath = await download(sources.geoNamesAdmin1, "admin1CodesASCII.txt");
  const citiesPath = path.join(work, "cities1000.txt");
  const unzip = spawnSync("unzip", ["-p", zipPath, "cities1000.txt"], { encoding: null, maxBuffer: 64 * 1024 * 1024 });
  if (unzip.status !== 0) throw new Error(unzip.stderr?.toString() || "Unable to extract cities1000.txt");
  writeFileSync(citiesPath, unzip.stdout);

  const adminNames = new Map();
  for (const line of readFileSync(adminPath, "utf8").split("\n")) {
    const [code, name, asciiName] = line.split("\t");
    if (code) adminNames.set(code, asciiName || name || "");
  }

  const importPath = path.join(work, "cities.tsv");
  const writer = createWriteStream(importPath);
  const lines = createInterface({ input: createReadStream(citiesPath), crlfDelay: Infinity });
  for await (const line of lines) {
    const fields = line.split("\t");
    if (fields.length < 19) continue;
    const [id, name, asciiName, , latitude, longitude, featureClass, featureCode, countryCode, , admin1Code, , , , population] = fields;
    const parsedLatitude = Number(latitude);
    const parsedLongitude = Number(longitude);
    if (!Number.isInteger(Number(id)) || !Number.isFinite(parsedLatitude) || !Number.isFinite(parsedLongitude) || Math.abs(parsedLatitude) > 90 || Math.abs(parsedLongitude) > 180) continue;
    if (featureClass !== "P") continue;
    const clean = (value) => String(value || "").replaceAll("\t", " ").replaceAll("\n", " ");
    const adminName = adminNames.get(`${countryCode}.${admin1Code}`) || "";
    writer.write([id, clean(name), clean(asciiName || name), latitude, longitude, countryCode, clean(adminName), featureCode, population || "0"].join("\t") + "\n");
  }
  writer.end();
  await new Promise((resolve, reject) => { writer.on("finish", resolve); writer.on("error", reject); });

  const databasePath = path.join(output, "cities.sqlite");
  rmSync(databasePath, { force: true });
  const sql = `
PRAGMA journal_mode=OFF;
PRAGMA synchronous=OFF;
PRAGMA page_size=4096;
CREATE TABLE cities(id INTEGER PRIMARY KEY, name TEXT NOT NULL, ascii_name TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, country_code TEXT NOT NULL, admin_name TEXT NOT NULL, feature_code TEXT NOT NULL, population INTEGER NOT NULL);
.mode tabs
.import '${importPath.replaceAll("'", "''")}' cities
CREATE VIRTUAL TABLE city_index USING rtree(id, min_latitude, max_latitude, min_longitude, max_longitude);
INSERT INTO city_index SELECT id, latitude, latitude, longitude, longitude FROM cities;
ANALYZE;
VACUUM;
`;
  const sqlite = spawnSync("sqlite3", [databasePath], { input: sql, encoding: "utf8" });
  if (sqlite.status !== 0) throw new Error(sqlite.stderr || "Unable to build cities.sqlite");
}

const countryCount = await buildCountries();
await buildCities();
const countryOutput = path.join(output, "countries.json");
const cityOutput = path.join(output, "cities.sqlite");
const digest = (filename) => createHash("sha256").update(readFileSync(filename)).digest("hex");
const rowCount = Number(spawnSync("sqlite3", [cityOutput, "SELECT count(*) FROM cities;"], { encoding: "utf8" }).stdout.trim());
const administrativeCenterCounts = Object.fromEntries(
  spawnSync("sqlite3", ["-separator", "\t", cityOutput, "SELECT feature_code, count(*) FROM cities WHERE feature_code IN ('PPLC','PPLA','PPLA2','PPLA3','PPLA4','PPLA5') GROUP BY feature_code ORDER BY feature_code;"], { encoding: "utf8" })
    .stdout.trim().split("\n").filter(Boolean).map((line) => { const [code, count] = line.split("\t"); return [code, Number(count)]; }),
);
const outputs = {
  countries: { bytes: statSync(countryOutput).size, sha256: digest(countryOutput), featureCount: countryCount },
  cities: { bytes: statSync(cityOutput).size, sha256: digest(cityOutput), rowCount, administrativeCenterCounts, filter: "all valid feature_class P rows from cities1000" },
};
if (outputs.countries.bytes > 25 * 1024 * 1024) throw new Error("countries.json exceeds 25 MB");
if (outputs.cities.bytes > 35 * 1024 * 1024) throw new Error("cities.sqlite exceeds 35 MB");
if (outputs.countries.featureCount < 250) throw new Error("country coverage unexpectedly incomplete");
if (outputs.cities.rowCount < 165_000) throw new Error("city coverage unexpectedly incomplete");
if (["PPLC", "PPLA", "PPLA2", "PPLA3", "PPLA4", "PPLA5"].some((code) => !administrativeCenterCounts[code])) throw new Error("administrative center coverage unexpectedly incomplete");
writeFileSync(path.join(output, "sources.json"), JSON.stringify({ generatedAt: "2026-07-12", sources, outputs }, null, 2) + "\n");
