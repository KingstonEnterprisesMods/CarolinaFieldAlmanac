CAROLINA FIELD ALMANAC  -  Farming Simulator 25
Version 1.0.6 (BETA)  -  Kingston Enterprises
Single player and multiplayer (one player hosts in the game). BETA in multiplayer.

==============================================================
WHAT IT DOES
==============================================================
Carolina Field Almanac puts real weather and real crop research into
your farm. Every number in the mod comes from a named source. It is
built from U.S. sources (NOAA, USDA, U.S. Extension services,
peer-reviewed papers), Canadian sources (Environment and Climate
Change Canada) and European sources (Poland, Germany, the UK, Ireland
and France - their weather services, agriculture ministries and crop
insurers). In Europe, crop insurance uses that country's own numbers,
not USDA. If no sourced number exists for something, the mod has no
effect on it.
The Sources tab in the game lists every number and where it came from.

WEATHER
- 426 NOAA weather stations in all 50 states, plus 84 stations in
  Canada's farm provinces (Alberta, Manitoba, Ontario, Quebec,
  Saskatchewan).
- When a new save starts, a window asks you to pick your station, and
  a red banner stays at the top of the screen until you do.
- Pick your State / Province, City and part of town:
  ESC -> Settings -> Field Almanac, or the Field Almanac page ->
  Settings tab.
- Each day's high, low, rain and sun come from 30 years of NOAA
  records (1991-2020). Rain timing, thunder, snow, humidity, wind
  and clouds follow NOAA hourly records for that station.
- The game's own forecast and sky follow these days.
- Canada: days, highs, lows and rain from the same NOAA daily records
  (Environment Canada data), 1991-2020. Hourly humidity, wind and sky
  from NOAA hourly records at the nearest Canadian airport. Rain timing
  from Environment Canada hourly rain (2002-2020). Canadian sky is
  counted below 12,000 ft, the way a U.S. airport sensor sees it; the
  two countries use different instruments, so sky is close, not equal.
- Gnadenthal map: Marquette, Manitoba is pre-selected (you confirm it).

CROPS (39 crop entries)
- Every field keeps its own growth clock (degree days) from
  planting, fed by the real weather.
- Damage that can cost yield at harvest, each from a named source:
  freeze, heat, hail, wind, tornado, hurricane / tropical storm,
  drought, waterlogging, flooding, rain on a ready crop and harvest
  delay.
- Tornado and hurricane chances come from USDA crop-insurance claims
  in YOUR station's state (a state that grows none of a crop uses
  the crop's lead state). A hurricane only hits on a rainy day, and
  it replaces that storm's own flood / rain loss when it is larger. Which crops get which damage is
  listed on the Sources tab.
- Corn: 95 F or hotter at pollination costs yield after 4 days.
- Peanuts: dug peanuts that freeze in the windrow become Seg 2 grade
  and keep 35 % of their value.
- Canola frost after flowering and fall-sown barley freeze.
- Black beans (Redstone County map).
- New in 0.27: pinto beans, lentils, chickpeas, flax, yellow mustard,
  proso millet, buckwheat, rye, triticale (Gnadenthal map) and onions
  (Ray County map), with growth stages, planting dates, hail, wind,
  freeze / frost / cold winter (USDA claims, only on freezing days) and
  insurance. Clover gets forage insurance. Drought is off for crops FAO
  gives no yield number for (Rule #1).
- Feed corn and feed bean (Sandy Hills Farms) use the corn and soybean
  numbers (same plants). Feed corn is insured like corn; feed bean is
  not insured (the soybean policy covers beans only).
- No effect yet (no sourced numbers): spelt, lavender, poppy and the
  flowering catch crop.
- You can switch each damage type on or off on the Settings tab.
- New in 0.28: EUROPE - POLAND, GERMANY, UK and IRELAND. Pick
  "Poland", your German state (for example "Bavaria (Germany)"), or
  "England (UK)", "Scotland (UK)", "Wales (UK)", "Northern Ireland (UK)"
  or "Ireland" in the station list: 54 Polish (IMGW), 274 German (DWD)
  and 81 UK Met Office stations, 1991-2020, same method as the U.S. and
  Canada, plus 10 Met Eireann stations for Ireland and 396 Meteo-France
  stations by French region (for example "Brittany (France)"). About 60 ModHub maps that name
  a real place pick their station for you (you still confirm it). Weather, growth, frost, drought,
  heat and hay curing all run. HAIL runs with real European yearly
  losses (Germany: GDV insurers 1991-2020; Poland: Ministry of
  Agriculture). POLAND has crop insurance with the Ministry's real
  numbers (one rate for all covered crops, pays the loss above 10 %).
  GERMANY has hail insurance like a real German hail policy (hail
  damage only, paid in full from 5 %, farmer pays the whole premium).
  Poland also gets spring frost and winter-kill from the Ministry's
  payouts. Off in Europe for now (no European numbers yet, Rule #1):
  wind, storms and German frost claims.
  UK and Ireland: hail, wind and insurance are off for now (no UK or
  Irish loss numbers yet). FRANCE has crop insurance with the real
  French all-weather (MRC) numbers; French hail is off for now.
  Data sources: IMGW-PIB; Deutscher Wetterdienst; GDV; MRiRW; Met
  Office MIDAS Open (contains public sector information licensed under
  the Open Government Licence v3.0); Met Eireann (CC BY 4.0); Meteo-France (Licence Ouverte v2.0); CCR.
  Canada: Environment and Climate Change Canada data - contains
  information licensed under the Open Government Licence - Canada.
- New in 1.0.6: the mod description, this README and the in-game
  texts are corrected. Carolina Field Almanac is NOT compatible with
  other weather or hay drying mods (see that section below); the old
  description wrongly said it worked with Moisture System and Realistic
  Water & Soil Management. The description now lists the Canada and
  Europe stations and European insurance, and old lines (4 % per wet
  day, hay curing days) are gone. Canadian data credit line added.
  Nothing changes in how the mod plays.
- New in 1.0.5: new NOAA station Monroe 26 N (LA), a NOAA climate
  reference site (humidity, wind and sky from Monroe Regional AP).
  Jones La and La-Ark Logging pre-pick it; AR River Lowlands pre-picks
  Pine Bluff; BlackRiver Farms pre-picks Alexandria (towns confirmed by
  the Delta South Modding & Mapping team).
- New in 1.0.4: 7 new NOAA weather stations near Delta South maps:
  Greenwood and Greenville (MS), Alexandria (LA), Jonesboro and
  Blytheville (AR), Cape Girardeau (MO) and Troy (AL). Cruger, Vance,
  Sherard, Cottonport, Delaplaine, Oran, Scott County, Goshen and
  Lauderdale County maps now pre-pick their nearest station.
  Map crops that are a type of corn, soybean or sorghum (non-GMO, eco,
  bio, food-grade, cattle-feed, early, new, organic, feed) use the plain
  crop's weather numbers and insurance (corn types: Corn policy; grain
  soybean types: Soybean policy; feed sorghum: Grain Sorghum policy;
  cattle-feed beans are not insured, same as feed beans).
- New in 1.0.3: the Field Cure box shows only when you are on or
  near the cut hay (within 50 m), not anywhere on a large farmland.
  Missed notices and the rain-on-hay line still show everywhere.
- New in 1.0.2: the Field Cure panel you see in a tractor now sits
  bottom-left, right above the mini map, next to the Field Almanac
  map icons. The box on foot is the game's own box and is unchanged.
- New in 1.0.1: hay curing follows the game calendar (days per month),
  the same way the crop clocks do. Each game day stands for the real
  days of that month, so on 1-day months you can cut one day and bale
  the next if it stays dry. Drying, dew, rain and respiration all scale
  the same way - cut at the right time: grass or silage has to be
  picked up quickly on short months, and hay cut too wet or right
  before rain can still be caught by the rain.
- New in 1.0.0: ModHub-ready cleanup (GIANTS TestRunner): game version 1.25.1 format, changelog, unused files removed. Nothing changes in how the mod plays.
- New in 0.30.1: once the weather station is confirmed, any "pick your weather station" warning still waiting in the game's notification line is removed, so an old warning no longer shows up after you picked.
- New in 0.30.0: MULTIPLAYER (one player hosts in the game).
  * The host runs the weather, crop clocks, damage, hay curing, insurance
    and saves. Every 2 seconds it sends the other players what changed;
    a player who joins gets everything once.
  * Everyone shares one weather station (one map, one sky). Changing the
    station or a shared setting (damage switches, mower conditions hay,
    light mode) is for the host or an admin.
  * Separate farms: each farm buys its own crop policies, pays its own
    premiums, gets its own claims, and gets the notices about its own
    fields, bales and silage. The Fields tab shows each field's farm.
  * Each player keeps their own pop-up settings (Notices, Pop-up time).
- New in 0.29.12: the "weather station confirmed" notice says how many
  crops were rebuilt from planting dates and how many start today, and
  says when insurance is off for the country.
- New in 0.29.11: rain or dry also follows the real days between game
  days, so with few days per month you no longer get long dry or wet runs
  that the station's records don't show.
  Drumard (Dundalk, Ireland) keeps its nearest weather station across the
  border but now uses Ireland's Teagasc planting dates.
  No day's high or low goes past what that station really recorded in
  that month in 1991-2020.
- New in 0.29.10: daily high and low now move together the way they do
  at the real station (measured from the same 1991-2020 records), so no more
  days like 52/51 F or 94/49 F turning up far more often than real. With
  few days per month, one warm or cold spell no longer carries over from
  one month into the next.
- New in 0.29.9: the forecast Sky column says "Rain" or "Snow" for the
  day instead of "Rain or snow".
- New in 0.29.8: Quebec planting dates from its variety trials, and Ontario
  dates from government advice (corn, soybeans, spring cereals).
- New in 0.29.7: Irish planting dates from Teagasc advice (winter wheat
  Oct 15, winter barley Oct 5, spring barley Mar 23).
- New in 0.29.6: Great Britain winter wheat (Oct 10) and winter barley
  (Sep 26) planting dates from AHDB crop reports.
  Polish planting dates from COBORU variety trials (mean
  sowing date of all trial sites, 2021-2025) for corn, spring and winter
  wheat, spring and winter barley, oats, rye and triticale.
- New in 0.29.5: Canadian planting dates for Alberta (May 19), Saskatchewan
  (May 18) and Manitoba (May 26) from the provincial crop reports' 5-year
  average, one date per province for spring crops. Ontario, Quebec and
  fall-sown crops still start the clock the day CFA first sees them.
- New in 0.29.4: French planting dates added. A crop on an older save that
  could not be rebuilt before gets one more try when the save loads.
- New in 0.29.3: crops already growing on a new save can now be rebuilt
  from planting in Germany and France (and get daily normals in Canada and all of
  Europe). Daily normals are made by NOAA's own method from each
  station's 1991-2020 daily records. German planting dates come from DWD
  crop records (2019-2023); French ones from FranceAgriMer Cere'Obs
  (5-year average 2021-2025, same 50 % rule as USDA). Countries without a
  sourced planting date (Northern Ireland and UK spring crops for now) still start
  the clock on the day CFA first sees the crop.
- New in 0.29.2: maps with their own silage corn (SILAGEMAIZE, for example
  the Ohio and Pichonniere maps) now use the corn numbers: weather, damage,
  silage moisture, early-chop yield and the Corn insurance policy.
- New in 0.29.1: Field Almanac page text is bold and bigger (15 px rows,
  14 px notes and Sources) so it is easier to read.
- New in 0.29.1: the Insurance tab note now says where the numbers come
  from in Europe (France, Poland, Germany) instead of the U.S. note.
  Corn that was already growing when CFA first saw it and could not be
  rebuilt from its planting (for example on European maps) shows
  "moisture not known" when chopped and has no yield change.
- New in 0.29: SILAGE.
  - While you chop, the moisture shows on screen (grass and alfalfa from
    the windrow, corn from its growth). Bunker target is 65-70 %. You get
    a warning over 70 % (leaks and spoils) or under 40 % (heats, can catch
    fire). Penn State; Oregon State.
  - Corn chopped too early gives less silage: at dent (73 % moisture) you
    get 87 % of the top yield, at 63 % you get it all (Penn State). Corn
    dries 0.75 points a day after dent.
  - Opened bunker silos: if you take silage off the face too slowly, part
    of what you take is spoiled and removed (Holmes & Muck 2007). Take at
    least the speed the notice shows for your season.
  - Both can be switched off on the Settings tab.
- New in 0.28.1: hay drying in Europe was checked against real European
  guidance (Ireland, Germany, Austria, France, Poland): 3-6 days from cut
  to hay in good weather. The mod matches, so nothing changed.

HAY - CAROLINA FIELD CURE
- Cut it, leave it lie, and let the sun cure it in the field. No
  tedder or dryer needed.
- Hay dries from sun, heat and dry air. It stops drying at night and
  takes back a little dew. Rain soaks it again.
- Tedding and raking are optional. Each has its own sourced loss.
- Mowing, raking and baler losses come from research.
- Grass becomes collectable hay at 20 % moisture (about 3 good
  real drying days; on short game months that fits in a day or two).
- Bales made too wet lose hay in storage. Above 34 % moisture the
  mod tells you to wrap the bale within 24 hours.
- Stand on a swath to see its moisture.

FORAGE
- Alfalfa is ready to cut again about one month after a cut. Grass
  takes about two months; one month after a cut it is about halfway
  back. (Alfalfa 26-35 days, UC IPM. Grass 30-60 days, Penn State
  Extension.) The base game takes three months for both, so this is
  not a bug.
- Alfalfa cutting order and late-fall cut rules.
- Winter can damage alfalfa and grass stands, using USDA and state
  research for your station.

CROP INSURANCE
- Buy a policy per crop BEFORE you plant: Yield Protection, Revenue
  Protection, RP-HPE or APH, 50-85 % coverage. Prices are from USDA
  RMA Summary of Business 2021-2025 (lead state).
- New save: the fields you own when the save starts can be insured
  that first season, even if the crop is already harvest-ready, as
  long as no damage was recorded (start-up cover - a game rule, not
  USDA). Fields you buy later with a crop already in them are not
  covered until their next planting (NPC farms have no insurance to
  transfer - USDA RMA Basic Provisions sec. 28).
- Every field of that crop is covered at planting. The policy renews
  each season until you cancel it. Claims are paid at harvest.
- Damage switches lock while an insured crop is in the field.
- Premiums and claims show on the game's Finances page in their own
  rows: "CFA Insurance Premium" and "CFA Insurance Claim".

==============================================================
WHERE TO SEE WHAT THE MOD IS DOING
==============================================================
- ESC -> Field Almanac page. Tabs: Notifications, Fields, Hay,
  Weather, Insurance, Settings, Sources.
- Map -> Field Info box: the real growth stage, and a Hay row while
  hay is curing.
- Field Cure box (on foot or in a vehicle): hay ready, driest and
  wettest moisture, and rain warnings. It hides with the game's HUD
  (Scroll Lock).
- Console (~), if enabled: cfaCrops, cfaWeather, cfaStation,
  cfaNotices, cfcInfo.

==============================================================
NOT COMPATIBLE WITH OTHER WEATHER OR HAY DRYING MODS
==============================================================
Carolina Field Almanac is built on real NOAA and Environment Canada
weather records (1991-2020 normals). Another weather mod replaces that
weather, and another hay drying mod fights with Field Cure, so these
mods are NOT compatible:
- Realistic Water & Soil Management (FS25_RealisticWaterSoilManagement)
- Moisture System (FS25_MoistureSystem)
- Improved Hay (FS25_ImprovedHay)
- Realistic Hay Drying (FS25_lsfmRealisticHayDrying)
If one of them is installed, the mod tells you when the save loads
(pop-up and Notifications tab). With one of the two weather mods, our
weather, crop weather damage, CFA crop insurance and Field Cure hay
curing all stay off until you remove it (hay does not dry at all
without CFA weather).
- Seasons-type mods that change the weather or the calendar can also
  fight with CFA. Use one weather mod.

==============================================================
NOT COVERED
==============================================================
- Coffee, bananas and the Beans & Alpacas map (South America) are
  not covered. CFA weather stations are in the U.S., Canada and Europe
  (Poland, Germany, UK, Ireland, France) only. Coffee and bananas grow
  the game's normal way.
- Canada: tornado, hurricane and alfalfa / grass winter-kill are off at
  Canadian stations (their numbers are U.S. state numbers). Hail, wind
  and insurance use each crop's U.S. lead state, the same as on every
  map.
- Crops with no sourced number get no effect from the mod.
- Multiplayer (new in 0.30): tested only with one player hosting in the
  game. Dedicated servers are not tested yet. The corn / windrow moisture
  line while chopping shows on the host's screen only (the warnings reach
  everyone on that farm as notices).

==============================================================
IF YOUR GAME STUTTERS, LAGS OR CRASHES
==============================================================
The mod measures itself while you play. In our tests (up to 600+
mods, and over 2,000 patches of curing hay) it used about 0.1 to 2 %
of the game's time. Check these first:

1. Graphics add-ons that hook into the game (ReShade and its
   add-ons, "neural" DLSS add-ons). A crash from these shows
   "Exception code 0xc0000374" in Windows Event Viewer. Turn the
   add-on off for one session. The game's own DLSS setting is fine.
2. Two mods doing the same job (see above).
3. Lots of hay on the ground on a slower PC: Field Almanac page ->
   Settings -> Light mode -> On. Hay dries exactly the same; the
   boxes and icons just update a few seconds later.
4. Too many vehicle "design" options. Some vehicle mods add dozens of
   extra design or color slots. Over 128 total, the game cannot load
   the shop. That is not this mod. Look in log.txt for "too many
   configuration types".

IS IT THIS MOD?
- Quit the game normally. Open:
  Documents\My Games\FarmingSimulator2025\log.txt
- Search for "performance". At every save the mod writes how much
  time it used ("% of real time") and its slowest frame.
- The game overwrites log.txt every time it starts, so copy it
  BEFORE you start the game again.
- Send that log with any bug report.

==============================================================
Author: Kingston Enterprises
