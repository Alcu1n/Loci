# Loci notices

Loci is an independent native iOS implementation of a map-poster workflow. It does not use the Terraink name, logo, or visual assets.

`Loci/Resources/loci-map-style.json` is an AGPL-3.0-or-later derivative based on the map-layer architecture, road classifications, and styling concepts in Terraink. Copyright notices for Terraink contributors and the complete corresponding source for this application must accompany every distributed build under AGPL-3.0-or-later.

The project includes MapLibre Native via Swift Package Manager. Map data, tiles, glyphs, sprites, and geocoding must be configured with providers whose terms allow the intended mobile usage. Before public distribution, add the selected providers' required attribution and privacy terms to the application configuration.

Country boundary lookup uses a coordinate-quantized derivative of Natural Earth Admin 0 Countries 1:10m version 5.1.2. Natural Earth data is in the public domain. Source: https://www.naturalearthdata.com/

Offline city and administrative-center lookup contains the complete valid populated-place rows from GeoNames `cities1000` plus `admin1CodesASCII` data downloaded on 2026-07-12, transformed and indexed as SQLite. GeoNames data is licensed under Creative Commons Attribution 4.0: https://creativecommons.org/licenses/by/4.0/. Source: https://www.geonames.org/. GeoNames provides the data as-is without warranty of accuracy, timeliness, or completeness.

If any Terraink AGPL-3.0-covered source is subsequently copied or adapted into Loci, retain its copyright and license notices and make the complete corresponding source available to recipients under AGPL-3.0. This initial native implementation contains no copied Terraink source files.
