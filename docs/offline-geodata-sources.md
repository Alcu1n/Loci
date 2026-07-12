# Offline geodata sources

This note fixes the provenance, licensing, and build inputs for the offline
country and city resolver bundled with Loci. Source archives are build inputs;
the app should ship only the generated, indexed subset.

## Country boundaries: Natural Earth

- Use [Natural Earth Admin 0 – Countries, 1:50m](https://www.naturalearthdata.com/downloads/50m-cultural-vectors/), pinned to repository tag `v5.1.2` and commit `f1890d9f152c896d250a77557a5751a93d494776`. Natural Earth describes 1:50m as suitable for zoomed-out country and regional maps; this matches Loci's country-label tier below zoom 10. The generated coordinate-quantized resource is 1.8 MB.
- Retain only the polygon geometry and stable lookup/display attributes such as ISO alpha-2/alpha-3 code, country name, English name, and continent. Handle antimeridian-crossing geometry explicitly.
- Natural Earth states that all its vector and raster map data is [public domain](https://www.naturalearthdata.com/about/terms-of-use/): modification, electronic distribution, and commercial use are allowed; attribution is optional. Acknowledging Natural Earth in third-party notices is still recommended.
- Boundary worldview is a product decision, not a geometry optimization. This build uses the default de facto dataset and must not silently mix it with the separately published China, Japan, ISO, or other point-of-view variants.

## Cities and administrative seats: GeoNames

- Use the official [`cities1000.zip`](https://download.geonames.org/export/dump/) dump as the source. The generated index explicitly retains cities with population at least 5,000 plus every `PPLA*` administrative seat present in `cities1000`. This documented filter preserves 108,829 records, including 62,806 administrative seats, while keeping the read-only SQLite and R-tree resource at 12 MB.
- Join [`admin1CodesASCII.txt`](https://download.geonames.org/export/dump/admin1CodesASCII.txt) (151,572 bytes when checked) to resolve first-level administrative names. Its four tab-separated fields are `code`, `name`, `asciiname`, and `geonameid`. [`countryInfo.txt`](https://download.geonames.org/export/dump/countryInfo.txt) may supply country metadata; ignore comment lines.
- GeoNames main dumps are UTF-8, tab-delimited rows with these ordered fields: `geonameid`, `name`, `asciiname`, `alternatenames`, `latitude`, `longitude`, `feature class`, `feature code`, `country code`, `cc2`, `admin1 code`, `admin2 code`, `admin3 code`, `admin4 code`, `population`, `elevation`, `dem`, `timezone`, and `modification date`. Keep only the IDs, names required by the UI, coordinates, feature code, country/admin code, and population in the bundled index.
- GeoNames publishes rolling daily snapshots rather than immutable semantic versions. Every generated artifact must therefore record the UTC download date, all source URLs, byte sizes, and SHA-256 hashes in a checked-in manifest.

### License and redistribution

GeoNames applies [CC BY 4.0](https://download.geonames.org/export/dump/) to the dump. The [CC BY 4.0 legal code](https://creativecommons.org/licenses/by/4.0/legalcode.en) expressly permits reproducing and sharing the material and producing, reproducing, and sharing adapted material (section 2); it also covers extraction and reuse of database contents (section 4). Therefore, redistributing a filtered and transformed SQLite/binary database inside the app is permitted, provided the attribution conditions are met.

The app and repository notices must:

- identify GeoNames and link to `https://www.geonames.org/`;
- identify the data as licensed under CC BY 4.0 and link to the license;
- say that Loci filtered, transformed, and indexed the source data;
- retain the source URL and no-warranty notice; and
- impose no additional terms or technical restrictions that prevent recipients from exercising the licensed rights in the included GeoNames material.

Suggested UI text:

> Contains GeoNames data, licensed under CC BY 4.0. Data has been filtered,
> transformed, and indexed for offline lookup.

## Reproducible generation pipeline

Implement one deterministic script and run it explicitly when updating data:

1. Download the pinned Natural Earth v5.1.2 GeoJSON and the dated GeoNames `cities1000` and `admin1CodesASCII` inputs into a temporary build directory and verify the SHA-256 hashes recorded in `scripts/build-offline-geodata.mjs`.
2. Read Natural Earth's WGS84 polygons, quantize coordinates, and retain only the documented attributes. The runtime point-in-polygon lookup normalizes ring longitude around the query point so antimeridian-crossing geometry remains usable.
3. Parse GeoNames as UTF-8 TSV using the published field order. Reject malformed coordinates/IDs, retain populated-place and administrative-seat records, join admin-1 names, normalize lookup strings, and preserve distinct legitimate places rather than deduplicating by name alone.
4. Write compact JSON country polygons and a deterministic read-only city database with a fixed schema, no build timestamps inside indexed rows, and an R-tree coordinate index. Run `VACUUM` only as the final generation step.
5. Emit a manifest containing generator version, generation/download dates, URLs, source hashes, row counts, schema version, and output hash. Fail the build if country data exceeds 3 MB, city data exceeds 15 MB, expected coverage drops unexpectedly, or attribution files are absent.
6. Test known points on continents, islands, coastlines, borders, and both sides of the antimeridian; test representative capital, regional-seat, and non-Latin city records. Compare a sample against online reverse geocoding, but do not make network results part of the deterministic build.
