# Location data curation (owner decision D6)

Date: 2026-11-17. Branch `feat/user-ux-redesign`. Applies to the data files referenced by `config.*_DATA_FILE`
(served by `GET /api/states` and `GET /api/states/{state}/cities`, and read by `api/index.py`).

Historical jobs are not touched: `jobs.cities_data` keeps the strings a job was created with, and
`locations.resolve_location()` still resolves removed strings (it indexes `removed_locations.json`).
Clients that hold a removed string in a draft or recent search should show it as **"No longer listed"**
and let the user decide; `data/removed_locations.json` (`{country: {region: [removed strings]}}`) lists them.

## Rules

a. **Exact duplicates** inside one region: keep the first occurrence, drop the rest. Not listed in
   `removed_locations.json` because the string is still listed.
b. **Qatar**: remove entries that are facilities or landmarks rather than places a business could be in
   (airports, ports/harbours/terminals/plants, museums, corniches, beaches, parks, marinas, bays, golf clubs,
   sports complexes, souqs/malls, university campuses, hospitals/health hubs, roads/streets, free zones),
   generic or invented labels ("Retail District", "Entertainment City", "Residential Area", "Northern
   Gateway" ...), and invented sub-labels of a place that is already listed (compass points such as
   "Umm Salal East", or "<place> City / New City / Downtown / Industrial / Farms") - Google Maps resolves those
   to the base place, so they can only return duplicates (de-duplicated, i.e. charged but empty).
   Real named localities and neighbourhoods are kept, even when spelt unusually or filed under the wrong region.
c. **Finland**: remove former municipalities that no longer exist after mergers (each listed below with the
   merger year and target). Only mergers known with confidence were applied.
d. **Entries without a comma** (UK, Indonesia): rewritten to `"Name, Region"`. The frontend already sent
   exactly this string for such entries (`_formatCityQuery` appends `", Region"`), so job strings, drafts and
   scraper input are unchanged. Not listed as removed.
e. Nothing else was renamed or removed. Misspellings, wrong regions and doubtful entries are listed under
   *Known issues (not changed)* for a later, deliberate pass.

Also fixed: **duplicate region keys** in the JSON (invalid JSON object; Python kept only the last block).
Indonesia `North Sumatra` had two identical blocks (collapsed, no visible change). Qatar `Doha` had two
different blocks: the first (real neighbourhoods such as West Bay, Al Dafna, Al Sadd, Msheireb) was never
served. Both blocks were merged in file order, then rules a/b applied - so some Doha entries are **newly
visible** (listed below).

## Counts per country

| Country | File | Entries in file | Served before | After | Duplicates removed | Rewritten (d) | Removed (b/c) |
|---|---|---:|---:|---:|---:|---:|---:|
| USA | `states_cities_data.json` | 9555 | 9555 | 9555 | 0 | 0 | 0 |
| UK | `uk_regions_cities.json` | 117 | 117 | 117 | 0 | 117 | 0 |
| UAE | `uae_cities_data.json` | 233 | 233 | 233 | 0 | 0 | 0 |
| KSA | `ksa_cities_data.json` | 283 | 283 | 283 | 0 | 0 | 0 |
| Australia | `australia_cities_data.json` | 763 | 763 | 763 | 0 | 0 | 0 |
| Canada | `canada_cities_data.json` | 390 | 390 | 388 | 2 | 0 | 0 |
| India | `india_cities_data.json` | 1020 | 1020 | 992 | 28 | 0 | 0 |
| Qatar | `qatar_cities_data.json` | 270 | 240 | 129 | 2 | 0 | 139 |
| Indonesia | `indonesia_cities_data.json` | 644 | 614 | 605 | 39 | 19 | 0 |
| Malaysia | `malaysia_cities_data.json` | 121 | 121 | 121 | 0 | 0 | 0 |
| Singapore | `singapore_cities_data.json` | 26 | 26 | 26 | 0 | 0 | 0 |
| China | `china_cities_data.json` | 249 | 249 | 249 | 0 | 0 | 0 |
| Finland | `finland_cities_data.json` | 330 | 330 | 254 | 3 | 0 | 73 |
| Germany | `germany_cities_data.json` | 450 | 450 | 449 | 1 | 0 | 0 |
| France | `france_cities_data.json` | 390 | 390 | 388 | 2 | 0 | 0 |
| **Total** | | 14841 | 14781 | 14552 | | | |

"Entries in file" counts both blocks of a duplicated region key; "Served before" is what the API returned.

## Duplicates removed (rule a)

- Canada / British Columbia: `Victoria, British Columbia`
- Canada / Yukon: `Dawson City, Yukon`
- India / Himachal Pradesh: `Rampur, Himachal Pradesh`
- India / Madhya Pradesh: `Betul, Madhya Pradesh`
- India / Mizoram: `Khawzawl, Mizoram`
- India / Punjab: `Malerkotla, Punjab`
- India / Rajasthan: `Jalore, Rajasthan`
- India / Tamil Nadu: `Villupuram, Tamil Nadu`
- India / Telangana: `Vikarabad, Telangana`; `Tandur, Telangana`; `Tandur, Telangana`; `Tandur, Telangana`; `Tandur, Telangana`; `Tandur, Telangana`; `Tandur, Telangana`; `Tandur, Telangana`; `Tandur, Telangana`; `Tandur, Telangana`; `Tandur, Telangana`; `Tandur, Telangana`; `Tandur, Telangana`; `Tandur, Telangana`; `Tandur, Telangana`; `Tandur, Telangana`; `Tandur, Telangana`
- India / Uttarakhand: `Nainital, Uttarakhand`; `Chopta, Uttarakhand`
- India / Andaman and Nicobar Islands: `Middle Andaman, Andaman and Nicobar Islands`; `Sentinel Island, Andaman and Nicobar Islands`
- India / Lakshadweep: `Kalpeni, Lakshadweep`
- Qatar / Doha: `Aspire Zone, Doha`
- Qatar / Al Rayyan: `New Al Rayyan, Al Rayyan`
- Indonesia / North Sumatra: second, identical copy of the whole region block (30 entries).
- Indonesia / Jambi: `Sungai Gelam, Jambi`
- Indonesia / West Java: `Purwakarta, West Java`; `Subang, West Java`
- Indonesia / Central Kalimantan: `Central Kalimantan`; `Central Kalimantan`; `Central Kalimantan`; `Muara Teweh, Central Kalimantan`
- Indonesia / Sulawesi Utara: `Sulawesi Utara`; `Sulawesi Utara`
- Finland / Satakunta: `Kullaa, Satakunta`; `Karvala, Satakunta`
- Finland / Northern Ostrobothnia: `Puolanka, Northern Ostrobothnia`
- Germany / North Rhine-Westphalia: `Düsseldorf, North Rhine-Westphalia`
- France / Normandy: `Honfleur, Normandy`; `Honfleur, Normandy`

Indonesia `Central Kalimantan` and `Sulawesi Utara` duplicates are the bare region name repeated, an artefact of
an earlier broken split of `"City, Region"` strings; `Muara Teweh` collided with the existing
`Muara Teweh, Central Kalimantan` after rewrite d.

## Rewritten to "Name, Region" (rule d)

- UK / Greater London: `City of London` -> `City of London, Greater London`; `Westminster` -> `Westminster, Greater London`; `Croydon` -> `Croydon, Greater London`; `Barnet` -> `Barnet, Greater London`; `Ealing` -> `Ealing, Greater London`; `Bromley` -> `Bromley, Greater London`; `Enfield` -> `Enfield, Greater London`; `Lambeth` -> `Lambeth, Greater London`; `Brent` -> `Brent, Greater London`; `Wandsworth` -> `Wandsworth, Greater London`; `Southwark` -> `Southwark, Greater London`; `Hillingdon` -> `Hillingdon, Greater London`; `Havering` -> `Havering, Greater London`; `Greenwich` -> `Greenwich, Greater London`; `Hackney` -> `Hackney, Greater London`; `Islington` -> `Islington, Greater London`; `Camden` -> `Camden, Greater London`
- UK / South East England: `Southampton` -> `Southampton, South East England`; `Portsmouth` -> `Portsmouth, South East England`; `Brighton` -> `Brighton, South East England`; `Reading` -> `Reading, South East England`; `Milton Keynes` -> `Milton Keynes, South East England`; `Oxford` -> `Oxford, South East England`; `Slough` -> `Slough, South East England`; `High Wycombe` -> `High Wycombe, South East England`; `Maidstone` -> `Maidstone, South East England`; `Basingstoke` -> `Basingstoke, South East England`; `Worthing` -> `Worthing, South East England`; `Eastbourne` -> `Eastbourne, South East England`; `Crawley` -> `Crawley, South East England`; `Gillingham` -> `Gillingham, South East England`; `Woking` -> `Woking, South East England`
- UK / North West England: `Manchester` -> `Manchester, North West England`; `Liverpool` -> `Liverpool, North West England`; `Warrington` -> `Warrington, North West England`; `Blackpool` -> `Blackpool, North West England`; `Bolton` -> `Bolton, North West England`; `Stockport` -> `Stockport, North West England`; `Preston` -> `Preston, North West England`; `Blackburn` -> `Blackburn, North West England`; `Oldham` -> `Oldham, North West England`; `St Helens` -> `St Helens, North West England`; `Rochdale` -> `Rochdale, North West England`; `Southport` -> `Southport, North West England`; `Salford` -> `Salford, North West England`; `Birkenhead` -> `Birkenhead, North West England`; `Wigan` -> `Wigan, North West England`
- UK / West Midlands: `Birmingham` -> `Birmingham, West Midlands`; `Coventry` -> `Coventry, West Midlands`; `Wolverhampton` -> `Wolverhampton, West Midlands`; `Solihull` -> `Solihull, West Midlands`; `Sutton Coldfield` -> `Sutton Coldfield, West Midlands`; `Dudley` -> `Dudley, West Midlands`; `Walsall` -> `Walsall, West Midlands`; `West Bromwich` -> `West Bromwich, West Midlands`; `Telford` -> `Telford, West Midlands`; `Stoke-on-Trent` -> `Stoke-on-Trent, West Midlands`; `Worcester` -> `Worcester, West Midlands`; `Shrewsbury` -> `Shrewsbury, West Midlands`
- UK / Yorkshire and the Humber: `Leeds` -> `Leeds, Yorkshire and the Humber`; `Sheffield` -> `Sheffield, Yorkshire and the Humber`; `Bradford` -> `Bradford, Yorkshire and the Humber`; `Hull` -> `Hull, Yorkshire and the Humber`; `York` -> `York, Yorkshire and the Humber`; `Huddersfield` -> `Huddersfield, Yorkshire and the Humber`; `Middlesbrough` -> `Middlesbrough, Yorkshire and the Humber`; `Doncaster` -> `Doncaster, Yorkshire and the Humber`; `Rotherham` -> `Rotherham, Yorkshire and the Humber`; `Wakefield` -> `Wakefield, Yorkshire and the Humber`; `Barnsley` -> `Barnsley, Yorkshire and the Humber`; `Halifax` -> `Halifax, Yorkshire and the Humber`; `Grimsby` -> `Grimsby, Yorkshire and the Humber`; `Scunthorpe` -> `Scunthorpe, Yorkshire and the Humber`
- UK / South West England: `Bristol` -> `Bristol, South West England`; `Plymouth` -> `Plymouth, South West England`; `Bournemouth` -> `Bournemouth, South West England`; `Poole` -> `Poole, South West England`; `Swindon` -> `Swindon, South West England`; `Gloucester` -> `Gloucester, South West England`; `Exeter` -> `Exeter, South West England`; `Cheltenham` -> `Cheltenham, South West England`; `Torquay` -> `Torquay, South West England`; `Bath` -> `Bath, South West England`; `Salisbury` -> `Salisbury, South West England`; `Taunton` -> `Taunton, South West England`; `Weymouth` -> `Weymouth, South West England`
- UK / East of England: `Norwich` -> `Norwich, East of England`; `Southend-on-Sea` -> `Southend-on-Sea, East of England`; `Luton` -> `Luton, East of England`; `Cambridge` -> `Cambridge, East of England`; `Ipswich` -> `Ipswich, East of England`; `Peterborough` -> `Peterborough, East of England`; `Colchester` -> `Colchester, East of England`; `Chelmsford` -> `Chelmsford, East of England`; `Basildon` -> `Basildon, East of England`; `Watford` -> `Watford, East of England`; `Bedford` -> `Bedford, East of England`; `Stevenage` -> `Stevenage, East of England`
- UK / East Midlands: `Leicester` -> `Leicester, East Midlands`; `Nottingham` -> `Nottingham, East Midlands`; `Derby` -> `Derby, East Midlands`; `Northampton` -> `Northampton, East Midlands`; `Mansfield` -> `Mansfield, East Midlands`; `Lincoln` -> `Lincoln, East Midlands`; `Chesterfield` -> `Chesterfield, East Midlands`; `Loughborough` -> `Loughborough, East Midlands`; `Corby` -> `Corby, East Midlands`; `Kettering` -> `Kettering, East Midlands`
- UK / North East England: `Newcastle upon Tyne` -> `Newcastle upon Tyne, North East England`; `Sunderland` -> `Sunderland, North East England`; `Gateshead` -> `Gateshead, North East England`; `Darlington` -> `Darlington, North East England`; `Hartlepool` -> `Hartlepool, North East England`; `South Shields` -> `South Shields, North East England`; `Tynemouth` -> `Tynemouth, North East England`; `Durham` -> `Durham, North East England`; `Stockton-on-Tees` -> `Stockton-on-Tees, North East England`
- Indonesia / Riau: `Kepulauan Riau` -> `Kepulauan Riau, Riau`; `Riau` -> `Riau, Riau`
- Indonesia / Jambi: `Sungai Gelam` -> `Sungai Gelam, Jambi`; `Jambi` -> `Jambi, Jambi`
- Indonesia / Lampung: `Lampung Barat` -> `Lampung Barat, Lampung`; `Lampung` -> `Lampung, Lampung`
- Indonesia / East Kalimantan: `Tabur` -> `Tabur, East Kalimantan`; `East Kalimantan` -> `East Kalimantan, East Kalimantan`
- Indonesia / Central Kalimantan: `Kualakapuas` -> `Kualakapuas, Central Kalimantan`; `Central Kalimantan` -> `Central Kalimantan, Central Kalimantan`; `Muara Teweh` -> `Muara Teweh, Central Kalimantan`; `Petai` -> `Petai, Central Kalimantan`; `Pulang Pisau` -> `Pulang Pisau, Central Kalimantan`
- Indonesia / West Kalimantan: `Malinau` -> `Malinau, West Kalimantan`; `West Kalimantan` -> `West Kalimantan, West Kalimantan`
- Indonesia / Sulawesi Utara: `Parepare` -> `Parepare, Sulawesi Utara`; `Sulawesi Utara` -> `Sulawesi Utara, Sulawesi Utara`; `Pangkep` -> `Pangkep, Sulawesi Utara`; `Gorontalo` -> `Gorontalo, Sulawesi Utara`

## Removed - Qatar (rule b)

Reason codes: F = facility / landmark; G = generic or invented label; S = invented sub-label of a listed place.

### Doha (35)

- `Corniche, Doha` - F
- `The Torch Doha, Doha` - F
- `Museum Area, Doha` - G
- `Souq Waqif, Doha` - F
- `Lagoona, Doha` - F
- `Aspire Zone, Doha` - F
- `Airport Road, Doha` - F
- `Abdulla bin Jassim Al Thani, Doha` - F
- `Central Business District, Doha` - G
- `Hamad International Airport, Doha` - F
- `Doha Port, Doha` - F
- `Qatar Museum, Doha` - F
- `Doha Corniche, Doha` - F
- `Souq Waqif District, Doha` - F
- `Islamic Museum Area, Doha` - F
- `Educational District, Doha` - G
- `Financial District, Doha` - G
- `Retail District, Doha` - G
- `Entertainment City, Doha` - G
- `Sports City, Doha` - F
- `Pearl District, Doha` - G
- `Marina District, Doha` - G
- `Beach Resort Area, Doha` - G
- `Heritage Area, Doha` - G
- `Modern Quarter, Doha` - G
- `Traditional Quarter, Doha` - G
- `Lusail District, Doha` - G
- `New Doha District, Doha` - G
- `Free Zone, Doha` - F
- `Warehouse District, Doha` - G
- `Logistics Center, Doha` - F
- `Exhibition Centers, Doha` - F
- `Convention Centers, Doha` - F
- `Healthcare Hub, Doha` - F
- `Wellness District, Doha` - G

### Al Rayyan (4)

- `Education City, Al Rayyan` - F
- `Aspire, Al Rayyan` - F
- `Al Waab Park, Al Rayyan` - F
- `Markhiya Park, Al Rayyan` - F

### Al Wakrah (16)

- `Souq Al Wakrah, Al Wakrah` - F
- `Al Jassasiya, Al Wakrah` - F
- `Mesaieed Port, Al Wakrah` - F
- `Wakrah Corniche, Al Wakrah` - F
- `Al Wakrah City, Al Wakrah` - S
- `Wakrah South, Al Wakrah` - S
- `Wakrah North, Al Wakrah` - S
- `Wakrah Beach, Al Wakrah` - F
- `Wakrah Seaside, Al Wakrah` - G
- `Industrial City, Al Wakrah` - G
- `Port Area, Al Wakrah` - G
- `Mesaieed Plant, Al Wakrah` - F
- `Wakrah Park, Al Wakrah` - F
- `New Wakrah District, Al Wakrah` - G
- `Wakrah Marina, Al Wakrah` - F
- `Dukhan Road, Al Wakrah` - F

### Al Khor (18)

- `Al Khor City, Al Khor` - S
- `Al Khor Beach, Al Khor` - F
- `Al Khor North, Al Khor` - S
- `Al Khor South, Al Khor` - S
- `Al Khor New City, Al Khor` - S
- `Ras Laffan Industrial City, Al Khor` - F
- `Al Khor Marina, Al Khor` - F
- `Al Khor Park, Al Khor` - F
- `Al Khor Water Front, Al Khor` - F
- `Al Khor Downtown, Al Khor` - S
- `Merjan Bay, Al Khor` - F
- `Simaisma Bay, Al Khor` - F
- `Al Khor Bay, Al Khor` - F
- `Tourism and Heritage Area, Al Khor` - G
- `Al Khor Golf Club, Al Khor` - F
- `Al Khor Fishery, Al Khor` - F
- `Al Khor Port, Al Khor` - F
- `Coastal Area, Al Khor` - G

### Umm Salal (14)

- `Umm Salal New City, Umm Salal` - S
- `Umm Salal North, Umm Salal` - S
- `Umm Salal South, Umm Salal` - S
- `Umm Salal Industrial, Umm Salal` - S
- `Umm Salal West, Umm Salal` - S
- `Umm Salal East, Umm Salal` - S
- `Dukhan Road, Umm Salal` - F
- `Umm Salal Marina, Umm Salal` - F
- `Umm Salal Park, Umm Salal` - F
- `Umm Salal Beach, Umm Salal` - F
- `Umm Salal Farms, Umm Salal` - S
- `Umm Salal Agriculture, Umm Salal` - S
- `Residential Area, Umm Salal` - G
- `Commercial Zone, Umm Salal` - G

### Ash Shahaniyah (9)

- `Ash Shahaniyah Farms, Qatar` - S
- `Ash Shahaniyah Industrial, Qatar` - S
- `Dukhan Oil Field, Qatar` - F
- `Al Shahaniya City, Qatar` - S
- `Simaisma Beach, Qatar` - F
- `Simaisma Park, Qatar` - F
- `Al Garafa South, Qatar` - S
- `Al Garafa North, Qatar` - S
- `Western Region, Qatar` - G

### Madinat Ash Shamal (14)

- `North Suburbs, Qatar` - G
- `Northern City, Qatar` - G
- `Doha North, Qatar` - S
- `North Marina, Qatar` - F
- `Lusail Marina, Qatar` - F
- `Lusail Beach, Qatar` - F
- `Lusail Marina District, Qatar` - G
- `Lusail Downtown, Qatar` - S
- `Lusail Retail District, Qatar` - G
- `Northern Gateway, Qatar` - G
- `Gateway to North, Qatar` - G
- `Northern Corridor, Qatar` - G
- `Shamal Park, Qatar` - F
- `Northern Resort, Qatar` - G

### Al Jumail (29)

- `Al Jumail Coastal, Qatar` - S
- `Al Jumail Port, Qatar` - F
- `Al Jumail Beach, Qatar` - F
- `Al Jumail Industrial, Qatar` - S
- `Al Jumail City, Qatar` - S
- `Al Jumail North, Qatar` - S
- `Al Jumail South, Qatar` - S
- `Al Jumail East, Qatar` - S
- `Al Jumail West, Qatar` - S
- `Ras Laffan Jumail, Qatar` - S
- `Jumail Petrochemical, Qatar` - F
- `Jumail Oil & Gas, Qatar` - F
- `Jumail Harbor, Qatar` - F
- `Jumail Marina, Qatar` - F
- `Jumail Dock, Qatar` - F
- `Jumail Shipyard, Qatar` - F
- `Industrial Port, Qatar` - F
- `Chemical Plant Area, Qatar` - F
- `LNG Terminal, Qatar` - F
- `Petrochemical Zone, Qatar` - F
- `Free Zone, Qatar` - F
- `Warehouse District, Qatar` - G
- `Logistics Hub, Qatar` - F
- `Coastal Highway, Qatar` - F
- `Northern Port, Qatar` - F
- `Loading Terminal, Qatar` - F
- `Shipping Center, Qatar` - F
- `Marine Services, Qatar` - G
- `Port Authority Area, Qatar` - G

## Removed - Finland (rule c)

| Region | Removed string | Merger |
|---|---|---|
| Uusimaa | `Pohja, Uusimaa` | merged into Raasepori (Raseborg), 2009 |
| Uusimaa | `Karjalohja, Uusimaa` | merged into Lohja, 2013 |
| Uusimaa | `Nummi-Pusula, Uusimaa` | merged into Lohja, 2013 |
| Uusimaa | `Sammatti, Uusimaa` | merged into Lohja, 2009 |
| Uusimaa | `Snappertuna, Uusimaa` | merged into Tammisaari (Ekenäs), 1977; now part of Raasepori |
| Varsinais-Suomi | `Yläne, Varsinais-Suomi` | merged into Pöytyä, 2009 |
| Varsinais-Suomi | `Kemiö, Varsinais-Suomi` | merged into Kemiönsaari, 2009 |
| Varsinais-Suomi | `Dragsfjärd, Varsinais-Suomi` | merged into Kemiönsaari, 2009 |
| Varsinais-Suomi | `Perniö, Varsinais-Suomi` | merged into Salo, 2009 |
| Varsinais-Suomi | `Halikko, Varsinais-Suomi` | merged into Salo, 2009 |
| Varsinais-Suomi | `Karjala, Varsinais-Suomi` | merged into Mynämäki, 1977 |
| Varsinais-Suomi | `Mietoinen, Varsinais-Suomi` | merged into Mynämäki, 2007 |
| Satakunta | `Kiukainen, Satakunta` | merged into Eura, 2009 |
| Satakunta | `Kullaa, Satakunta` | merged into Ulvila, 2005 |
| Satakunta | `Ahlainen, Satakunta` | merged into Pori, 1967 |
| Satakunta | `Noormarkku, Satakunta` | merged into Pori, 2010 |
| Satakunta | `Tyrvää, Satakunta` | merged into Vammala, 1973 (Vammala is now part of Sastamala) |
| Kanta-Häme | `Renko, Kanta-Häme` | merged into Hämeenlinna, 2009 |
| Kanta-Häme | `Lammi, Kanta-Häme` | merged into Hämeenlinna, 2009 |
| Kanta-Häme | `Aitolahti, Kanta-Häme` | merged into Tampere, 1966 |
| Kanta-Häme | `Viiala, Kanta-Häme` | merged with Toijala into Akaa, 2007 |
| Kanta-Häme | `Kalvola, Kanta-Häme` | merged into Hämeenlinna, 2009 |
| Kanta-Häme | `Sääksmäki, Kanta-Häme` | merged into Valkeakoski, 1973 |
| Kanta-Häme | `Hauho, Kanta-Häme` | merged into Hämeenlinna, 2009 |
| Kanta-Häme | `Tuulos, Kanta-Häme` | merged into Hämeenlinna, 2009 |
| Pirkanmaa | `Mäntä, Pirkanmaa` | (misspelling of Mänttä) merged with Vilppula into Mänttä-Vilppula, 2009 |
| Pirkanmaa | `Vilppula, Pirkanmaa` | merged with Mänttä into Mänttä-Vilppula, 2009 |
| Pirkanmaa | `Toijala, Pirkanmaa` | merged with Viiala into Akaa, 2007 |
| Pirkanmaa | `Kylmäkoski, Pirkanmaa` | merged into Akaa, 2011 |
| Pirkanmaa | `Äetsä, Pirkanmaa` | merged into Sastamala, 2009 |
| Pirkanmaa | `Kuorevesi, Pirkanmaa` | merged into Jämsä, 2001 |
| Pirkanmaa | `Ylistaro, Pirkanmaa` | merged into Seinäjoki, 2009 |
| Päijät-Häme | `Koski Hlk, Päijät-Häme` | Koski Hl. was renamed Hämeenkoski (1995) and merged into Hollola, 2016 |
| Päijät-Häme | `Artjärvi, Päijät-Häme` | merged into Orimattila, 2011 |
| Päijät-Häme | `Sumiainen, Päijät-Häme` | merged into Äänekoski, 2007 |
| Päijät-Häme | `Jämsänkoski, Päijät-Häme` | merged into Jämsä, 2009 |
| Kymenlaakso | `Anjalankoski, Kymenlaakso` | merged into Kouvola, 2009 |
| Kymenlaakso | `Kuusankoski, Kymenlaakso` | merged into Kouvola, 2009 |
| Kymenlaakso | `Elimäki, Kymenlaakso` | merged into Kouvola, 2009 |
| Kymenlaakso | `Vehkalahti, Kymenlaakso` | merged into Hamina, 2003 |
| Kymenlaakso | `Valkeala, Kymenlaakso` | merged into Kouvola, 2009 |
| Kymenlaakso | `Uukuniemi, Kymenlaakso` | merged into Parikkala, 2005 |
| Kymenlaakso | `Punkaharjun, Kymenlaakso` | (genitive form of Punkaharju) merged into Savonlinna, 2013 |
| Kymenlaakso | `Kerimäki, Kymenlaakso` | merged into Savonlinna, 2013 |
| Kymenlaakso | `Ristiina, Kymenlaakso` | merged into Mikkeli, 2013 |
| Kymenlaakso | `Kangaslampi, Kymenlaakso` | merged into Varkaus, 2005 |
| Kymenlaakso | `Virtasalmi, Kymenlaakso` | merged into Pieksänmaa, 2004 (Pieksänmaa merged into Pieksämäki, 2007) |
| South Karelia | `Uukuniemi, South Karelia` | merged into Parikkala, 2005 |
| South Karelia | `Anttola, South Karelia` | merged into Mikkeli, 2001 |
| South Karelia | `Virtasalmi, South Karelia` | merged into Pieksänmaa, 2004 (Pieksänmaa merged into Pieksämäki, 2007) |
| South Karelia | `Kangaslampi, South Karelia` | merged into Varkaus, 2005 |
| South Karelia | `Haukivuori, South Karelia` | merged into Mikkeli, 2007 |
| South Karelia | `Jäppilä, South Karelia` | merged into Pieksänmaa, 2004 (Pieksänmaa merged into Pieksämäki, 2007) |
| South Karelia | `Ristiina, South Karelia` | merged into Mikkeli, 2013 |
| South Karelia | `Kerimäki, South Karelia` | merged into Savonlinna, 2013 |
| South Karelia | `Punkaharjun, South Karelia` | (genitive form of Punkaharju) merged into Savonlinna, 2013 |
| South Karelia | `Punkaharju, South Karelia` | merged into Savonlinna, 2013 |
| South Karelia | `Valkeala, South Karelia` | merged into Kouvola, 2009 |
| South Karelia | `Vehkalahti, South Karelia` | merged into Hamina, 2003 |
| Northern Savonia | `Muuruvesi, Northern Savonia` | merged into Juankoski, 1971 (Juankoski merged into Kuopio, 2017) |
| Northern Savonia | `Nilsiä, Northern Savonia` | merged into Kuopio, 2013 |
| Northern Savonia | `Maaninka, Northern Savonia` | merged into Kuopio, 2015 |
| Northern Savonia | `Riistavesi, Northern Savonia` | merged into Kuopio, 1973 |
| Northern Savonia | `Karttula, Northern Savonia` | merged into Kuopio, 2011 |
| Eastern Savonia | `Tuupovaara, Eastern Savonia` | merged into Joensuu, 2005 |
| Eastern Savonia | `Vuolijoki, Eastern Savonia` | merged into Kajaani, 2007 |
| Eastern Savonia | `Leppävesi, Eastern Savonia` | merged into Laukaa, 1969 |
| Northern Ostrobothnia | `Oulunsalo, Northern Ostrobothnia` | merged into Oulu, 2013 |
| Northern Ostrobothnia | `Ylikiiminki, Northern Ostrobothnia` | merged into Oulu, 2013 |
| Northern Ostrobothnia | `Kiiminki, Northern Ostrobothnia` | merged into Oulu, 2013 |
| Northern Ostrobothnia | `Haukipudas, Northern Ostrobothnia` | merged into Oulu, 2013 |
| Northern Ostrobothnia | `Yli-Ii, Northern Ostrobothnia` | merged into Oulu, 2013 |
| Northern Ostrobothnia | `Muurla, Northern Ostrobothnia` | merged into Salo, 2009 |

## Newly visible (Qatar / Doha, from the previously shadowed first block)

22 entries: `Doha, Qatar`; `Al Marjan, Doha`; `Al Dafna, Doha`; `West Bay, Doha`; `Lusail, Doha`; `Pearl Qatar, Doha`; `Old Doha, Doha`; `Bin Mahmoud, Doha`; `Porto Arabia, Doha`; `Msheireb Downtown Doha, Doha`; `Al Fardan, Doha`; `Al Waab, Doha`; `Barwa Village, Doha`; `Sothea, Doha`; `Meadows, Doha`; `Khalifa City, Doha`; `Al Garafa, Doha`; `Galiery Doha, Doha`; `Rumaillah, Doha`; `Manara, Doha`; `Onaiza, Doha`; `Al Sadd, Doha`

## Kept although doubtful (rule e - not removed without certainty)

- Qatar: `Porto Arabia, Doha` (marina precinct on The Pearl), `Barwa Village, Doha` (commercial compound),
  `Galiery Doha, Doha`, `Sothea, Doha`, `Al Marjan, Doha`, `Al Fardan, Doha`, `Old Doha, Doha` (unverified names);
  `Al Wakrah Doha, Al Wakrah`, `New Al Wakrah, Al Wakrah`, `New Umm Salal, Umm Salal`, `Old Al Khor, Al Khor`,
  `Oryx Village, Al Khor`, `Jassim, Al Khor` (probably invented, not certain);
  `Ras Laffan, *` (industrial city, but a real named place); `Al Jumail, Qatar` (abandoned village - kept so the
  region is not empty; the region itself is not a Qatari municipality).
- Qatar spelling variants kept side by side: `Umm Salal Muhammad` / `Umm Salal Mohammed`,
  `New Al Rayyan` / `Jadeed Al Rayyan`, `Doha Al Jadida` / `New Doha`.
- Qatar removals of real places under an invented label (not renamed, per rule e): `Pearl District, Doha`
  (The Pearl - `Pearl Qatar, Doha` remains), `Lusail District, Doha` (`Lusail, Doha` / `Lusail City, Qatar` remain),
  `Souq Waqif` (market, treated like a mall).
- Finland: merged municipalities such as Haukipudas, Kiiminki, Kuusankoski, Toijala or Kemiö are still real
  localities (now districts/villages) where businesses exist. They were removed per decision D6; their parent
  municipality stays listed. Re-adding any of them is a one-line data change.

## Known issues (not changed)

- Qatar: many entries sit in the wrong region (e.g. `Al Sadd, Qatar` and `Onaiza, Qatar` under Madinat Ash Shamal,
  `Umm Salal, Al Wakrah`, `Lusail, Doha`); regions mix `", Qatar"` and `", <municipality>"` suffixes; Al Daayen
  municipality is missing; `Doha` has few neighbourhoods.
- Finland: entries filed under the wrong region (Åland municipalities under Uusimaa and Varsinais-Suomi,
  `Jyväskylä` under Päijät-Häme and Eastern Savonia, `Simo` under Pirkanmaa, `Haapavesi`/`Taivalkoski` under
  Satakunta ...); misspellings/genitive forms (`Forssan`, `Luhangan`, `Kiuruvetsi`); names that are not
  municipalities or are not places at all (`Uimahalli` = swimming hall, `Tulevat` = "upcoming", `Polku` = path,
  `Heikintöntie` = a street, `Kuopio North/South/East/West`); `Kuusjärvi` (renamed Outokumpu in 1968 - a rename,
  not a merger, so left in place).
- Indonesia: `Region, Region` entries produced by rule d (`Riau, Riau`, `Lampung, Lampung`,
  `East Kalimantan, East Kalimantan` ...) and cities filed under the wrong province (e.g. Pekanbaru, Batam and
  Jambi under North Sumatra; Parepare and Gorontalo under Sulawesi Utara).
- KSA: some entries use the city as suffix (`Al Hamra, Jeddah` under `Makkah Region`); job location derivation
  resolves these by exact match, so they report region `Makkah Region`.

## Reproducing

The curation was applied by a one-off script (not kept in the repo). To verify: `tests/test_user_ux_api.py`
checks that every entry has a comma, no region has duplicates or duplicate keys, every string in
`removed_locations.json` is absent from the data files yet still resolves, and that this document names every
removed entry.
