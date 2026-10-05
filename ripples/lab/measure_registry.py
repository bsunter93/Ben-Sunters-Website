"""Measure v1 registry: every stone, outcome, control pool, comparison group, decoy rule and known positive, frozen in
ripples/docs/measure_plan_v1.md before any outcome value was fetched. ripples/lab/measure_v1.py reads only this file.

Dates are US release (first US theatrical release, TV premiere, Broadway opening night) or date of death, as in the public
record; each was checked against Wikidata before registration (measure_plan_v1.md section 2). A stone dated on or after
the 25th of a month starts its window the next month (ladder2.ref_month).
"""
from __future__ import annotations

# ---------------------------------------------------------------- arm A: CDC WONDER, monthly deaths, US national
# Outcome series (D76, Underlying Cause of Death 1999-2020, by month of death, national only: the API allows no location).
# Each is one request; WONDER asks for one query at a time, about 2 minutes apart.
WONDER_SERIES = {
    # key: (label, single-year ages or None for all ages, injury intent, mechanism or None)
    "suicide_10_17": ("Suicide deaths, ages 10 to 17", list(range(10, 18)), "suicide", None),
    "suicide_10_19": ("Suicide deaths, ages 10 to 19", list(range(10, 20)), "suicide", None),
    "suicide_18_29": ("Suicide deaths, ages 18 to 29", list(range(18, 30)), "suicide", None),
    "suicide_30_64": ("Suicide deaths, ages 30 to 64", list(range(30, 65)), "suicide", None),
    "suicide_all_by_mechanism": ("Suicide deaths, all ages, by injury mechanism", None, "suicide", "by mechanism"),
}

WONDER_MARKS = [
    {"id": "13rw-youth", "stone": "13 Reasons Why", "slug": "13-reasons-why", "engine_mark": "w0", "stone_date": "2017-03-31",
     "kind": "teen_tv", "outcome": "suicide_10_17", "design": "yoy", "h": 3, "direction": "up",
     "what": "Suicide deaths among 10 to 17 year olds in April to June 2017 against April to June 2016, compared with the same "
             "three-month year-over-year change at every earlier month since 2000",
     "gradient": {"mode": "ordered", "groups": [["suicide_10_17", 3, "ages 10-17 (the show's audience)"],
                                                ["suicide_18_29", 2, "ages 18-29"], ["suicide_30_64", 1, "ages 30-64"]]},
     "secondary": [{"outcome": "suicide_10_19", "design": "yoy", "h": 3, "note": "Niederkrotenthaler et al. 2019 age band"},
                   {"outcome": "suicide_10_17", "design": "yoy", "h": 1, "note": "April 2017 alone (Bridge et al. 2020)"},
                   {"outcome": "suicide_10_17", "design": "standard", "h": 12, "note": "the ladder's 12-month design"}],
     "known_positive": {"published": True, "sources": [
         "Bridge JA et al. (2020), Journal of the American Academy of Child and Adolescent Psychiatry 59(2): 236-243: suicide "
         "among 10 to 17 year olds rose 28.9% above forecast in April 2017",
         "Niederkrotenthaler T et al. (2019), JAMA Psychiatry 76(9): 933-940: about 13% more suicides than expected among 10 to 19 "
         "year olds in April to June 2017"], "note": "disputed: Romer D (2020), PLOS ONE, attributes part of the rise to trend"}},
    {"id": "williams-all", "stone": "The death of Robin Williams", "slug": None, "engine_mark": None, "stone_date": "2014-08-11",
     "kind": "celebrity_death", "outcome": "suicide_all", "design": "yoy", "h": 5, "direction": "up",
     "what": "Suicide deaths, all ages, in August to December 2014 against August to December 2013, compared with the same "
             "five-month year-over-year change at every earlier month since 2000",
     "gradient": {"mode": "ordered", "groups": [["suicide_mech_reported", 2, "the method category reported in coverage"],
                                                ["suicide_mech_other", 1, "all other method categories"]]},
     "secondary": [{"outcome": "suicide_all", "design": "standard", "h": 12, "note": "the ladder's 12-month design"}],
     "known_positive": {"published": True, "sources": [
         "Fink DS, Santaella-Tenorio J, Keyes KM (2018), PLOS ONE 13(2): e0191405: 9.85% more suicides than expected in "
         "August to December 2014"], "note": None}},
]

# Matched control stones for arm A (same kind, nearest in time, no link to the outcome).
TEEN_TV = [  # teen-audience TV series premieres; linked ones are listed in LINKED_A and never used
    ("Gossip Girl", "2007-09-19"), ("Pretty Little Liars", "2010-06-08"), ("Skins (American TV series)", "2011-01-17"),
    ("Teen Wolf (2011 TV series)", "2011-06-05"), ("Switched at Birth (TV series)", "2011-06-06"), ("Awkward (TV series)", "2011-07-19"),
    ("The Fosters (American TV series)", "2013-06-03"), ("The 100 (TV series)", "2014-03-19"), ("Faking It (2014 TV series)", "2014-04-22"),
    ("Shadowhunters", "2016-01-12"), ("Degrassi: Next Class", "2016-01-15"), ("Stranger Things", "2016-07-15"),
    ("Riverdale (2017 TV series)", "2017-01-26"), ("Atypical", "2017-08-11"), ("Big Mouth (American TV series)", "2017-09-29"),
    ("Stranger Things season 2", "2017-10-27"), ("The End of the F***ing World", "2018-01-05"), ("Everything Sucks!", "2018-02-16"),
    ("On My Block", "2018-03-16"), ("Insatiable (TV series)", "2018-08-10"), ("Elite (TV series)", "2018-10-05"),
    ("Chilling Adventures of Sabrina (TV series)", "2018-10-26"), ("Sex Education (TV series)", "2019-01-11"),
    ("The Society (TV series)", "2019-05-10"), ("Stranger Things season 3", "2019-07-04"),
]
CELEB_DEATHS = [  # deaths of widely known public figures not by suicide (date of death)
    ("Elizabeth Taylor", "2011-03-23"), ("Amy Winehouse", "2011-07-23"), ("Steve Jobs", "2011-10-05"),
    ("Whitney Houston", "2012-02-11"), ("Andy Griffith", "2012-07-03"), ("Neil Armstrong", "2012-08-25"),
    ("James Gandolfini", "2013-06-19"), ("Paul Walker", "2013-11-30"), ("Nelson Mandela", "2013-12-05"),
    ("Philip Seymour Hoffman", "2014-02-02"), ("Joan Rivers", "2014-09-04"), ("Leonard Nimoy", "2015-02-27"),
    ("B.B. King", "2015-05-14"), ("David Bowie", "2016-01-10"), ("Prince (musician)", "2016-04-21"),
    ("Muhammad Ali", "2016-06-03"), ("Gene Wilder", "2016-08-29"), ("Carrie Fisher", "2016-12-27"),
    ("Tom Petty", "2017-10-02"), ("Stephen Hawking", "2018-03-14"), ("Aretha Franklin", "2018-08-16"),
    ("John McCain", "2018-08-25"), ("Stan Lee", "2018-11-12"), ("George H. W. Bush", "2018-11-30"),
    ("Luke Perry", "2019-03-04"), ("Toni Morrison", "2019-08-05"), ("Michael Jackson", "2009-06-25"),
    ("Patrick Swayze", "2009-09-14"), ("Farrah Fawcett", "2009-06-25"), ("Heath Ledger", "2008-01-22"),
    ("Anna Nicole Smith", "2007-02-08"), ("Steve Irwin", "2006-09-04"), ("Johnny Cash", "2003-09-12"),
    ("Ronald Reagan", "2004-06-05"), ("Ray Charles", "2004-06-10"), ("Pope John Paul II", "2005-04-02"),
]
# Stones linked to the arm-A outcomes: never a control or a decoy there (named before any data).
LINKED_A = {
    "13 Reasons Why season 2": "the same show, May 18, 2018", "Euphoria (American TV series)": "depicts overdose and self-harm",
    "13-reasons-why": "the stone itself", "parkland": "deaths of teenagers", "sandy-hook": "deaths of children",
    "columbine-active-shooter": "deaths of teenagers", "virginia-tech": "deaths of students", "uvalde": "deaths of children",
    "september-11": "a national shock with published suicide studies", "anthrax": "same window as September 11",
    "las-vegas-2017": "mass casualty event", "pulse": "mass casualty event", "boston-marathon": "mass casualty event",
}

# ---------------------------------------------------------------- arm B: NPS monthly recreation visits by park unit
# A stone whose featured unit is the setting or the subject of the work. Units in a family are summed.
NPS_MARKS = [
    {"id": "civil-war-burns", "stone": "The Civil War (Ken Burns)", "date": "1990-09-23", "kind": "documentary",
     "units": ["GETT", "ANTI", "MANA", "VICK", "SHIL", "FRSP", "CHCH", "PETE", "RICH", "STRI"], "group": "BATTLE",
     "why": "a nine-part PBS series on the war; the ten major Civil War battlefield parks are its settings"},
    {"id": "son-of-morning-star", "stone": "Son of the Morning Star", "date": "1991-02-03", "kind": "tv",
     "units": ["LIBI"], "group": "BATTLE", "why": "ABC miniseries on Custer and the Battle of the Little Bighorn"},
    {"id": "gettysburg-film", "stone": "Gettysburg (film)", "date": "1993-10-08", "kind": "film",
     "units": ["GETT"], "group": "BATTLE", "why": "the battle is the whole film"},
    {"id": "andersonville-tnt", "stone": "Andersonville (film)", "date": "1996-03-03", "kind": "tv",
     "units": ["ANDE"], "group": "BATTLE", "why": "TNT film set entirely in the Andersonville prison camp"},
    {"id": "lewis-clark-burns", "stone": "Lewis & Clark: The Journey of the Corps of Discovery", "date": "1997-11-04",
     "kind": "documentary", "units": ["LEWI"], "alt_codes": {"LEWI": ["FOCL"]}, "group": "HIST",
     "why": "PBS series on the expedition; Fort Clatsop is its winter camp"},
    {"id": "the-patriot", "stone": "The Patriot (2000 film)", "date": "2000-06-28", "kind": "film",
     "units": ["COWP"], "group": "BATTLE", "why": "the film's climactic battle is modeled on Cowpens"},
    {"id": "jazz-burns", "stone": "Jazz (miniseries)", "date": "2001-01-08", "kind": "documentary",
     "units": ["JAZZ"], "alt_codes": {"JAZZ": ["NOJA", "JELA"]}, "group": "HIST",
     "why": "PBS series on jazz; New Orleans Jazz National Historical Park interprets its birthplace"},
    {"id": "pearl-harbor-film", "stone": "Pearl Harbor (film)", "date": "2001-05-25", "kind": "film",
     "units": ["VALR"], "alt_codes": {"VALR": ["USAR"]}, "group": "HIST", "why": "the attack is the film's subject"},
    {"id": "gods-and-generals", "stone": "Gods and Generals (film)", "date": "2003-02-21", "kind": "film",
     "units": ["FRSP"], "group": "BATTLE", "why": "Fredericksburg and Chancellorsville are its battles"},
    {"id": "cold-mountain", "stone": "Cold Mountain (film)", "date": "2003-12-25", "kind": "film",
     "units": ["PETE"], "group": "BATTLE", "why": "opens with the Battle of the Crater at Petersburg"},
    {"id": "national-treasure", "stone": "National Treasure (film)", "date": "2004-11-19", "kind": "film",
     "units": ["INDE"], "group": "HIST", "why": "the hunt ends at Independence Hall and the Liberty Bell"},
    {"id": "grizzly-man", "stone": "Grizzly Man", "date": "2005-08-12", "kind": "documentary",
     "units": ["KATM"], "group": "NP", "why": "filmed in Katmai, where Timothy Treadwell lived among the bears"},
    {"id": "united-93", "stone": "United 93 (film)", "date": "2006-04-28", "kind": "film",
     "units": ["FLNI"], "group": "HIST", "why": "the flight that crashed at the memorial's site"},
    {"id": "into-the-wild", "stone": "Into the Wild (film)", "date": "2007-09-21", "kind": "film",
     "units": ["DENA"], "group": "NP", "why": "set on the Stampede Trail at the edge of Denali"},
    {"id": "the-war-burns", "stone": "The War (miniseries)", "date": "2007-09-23", "kind": "documentary",
     "units": ["WWII"], "group": "HIST", "why": "PBS series on the Second World War"},
    {"id": "127-hours", "stone": "127 Hours", "date": "2010-11-05", "kind": "film",
     "units": ["CANY"], "group": "NP", "why": "set in Blue John Canyon beside Canyonlands' Horseshoe Canyon unit"},
    {"id": "red-tails", "stone": "Red Tails", "date": "2012-01-20", "kind": "film",
     "units": ["TUAI"], "group": "HIST", "why": "the Tuskegee Airmen are its subject"},
    {"id": "lincoln-ford", "stone": "Lincoln (film)", "date": "2012-11-09", "kind": "film",
     "units": ["FOTH"], "group": "HIST", "why": "Lincoln's assassination at Ford's Theatre ends the film"},
    {"id": "lincoln-home", "stone": "Lincoln (film)", "date": "2012-11-09", "kind": "film",
     "units": ["LIHO"], "group": "HIST", "why": "Lincoln is its subject; Lincoln Home is his Springfield house"},
    {"id": "bears-disneynature", "stone": "Bears (2014 film)", "date": "2014-04-18", "kind": "documentary",
     "units": ["KATM"], "group": "NP", "why": "Disneynature film shot in Katmai"},
    {"id": "roosevelts-burns", "stone": "The Roosevelts", "date": "2014-09-14", "kind": "documentary",
     "units": ["HOFR", "ELRO", "SAHI", "THRB", "THRO"], "group": "HIST", "why": "PBS series on Theodore, Franklin and Eleanor Roosevelt"},
    {"id": "selma-film", "stone": "Selma (film)", "date": "2014-12-25", "kind": "film",
     "units": ["SEMO"], "group": "HIST", "why": "the 1965 marches from Selma to Montgomery are its subject"},
    {"id": "hamilton-grange", "stone": "Hamilton (musical)", "date": "2015-08-06", "kind": "stage",
     "units": ["HAGR"], "group": "HIST", "why": "Hamilton Grange is Alexander Hamilton's house",
     "known_positive": {"published": False, "sources": ["press reports in 2016 of rising visits to Hamilton Grange after the musical"]}},
    {"id": "vietnam-war-burns", "stone": "The Vietnam War (TV series)", "date": "2017-09-17", "kind": "documentary",
     "units": ["VIVE"], "group": "HIST", "why": "PBS series on the war; the Vietnam Veterans Memorial"},
    {"id": "yellowstone-tv", "stone": "Yellowstone (American TV series)", "date": "2018-06-20", "kind": "tv",
     "units": ["YELL"], "group": "NP", "why": "named for the park and set beside it in Montana"},
    {"id": "free-solo", "stone": "Free Solo", "date": "2018-09-28", "kind": "documentary",
     "units": ["YOSE"], "group": "NP", "why": "Alex Honnold's climb of El Capitan"},
    # registered and expected to be untestable (excluded period or no history); run anyway so the reason is recorded
    {"id": "national-treasure-2", "stone": "National Treasure: Book of Secrets", "date": "2007-12-21", "kind": "film",
     "units": ["MORU"], "group": "HIST", "why": "the hunt ends at Mount Rushmore"},
    {"id": "john-adams-hbo", "stone": "John Adams (miniseries)", "date": "2008-03-16", "kind": "tv",
     "units": ["ADAM"], "group": "HIST", "why": "HBO miniseries; Adams National Historical Park is the family home"},
    {"id": "twilight-olympic", "stone": "Twilight (2008 film)", "date": "2008-11-21", "kind": "film",
     "units": ["OLYM"], "group": "NP", "why": "set in Forks on the Olympic Peninsula"},
    {"id": "national-parks-burns", "stone": "The National Parks: America's Best Idea", "date": "2009-09-27", "kind": "documentary",
     "units": ["YELL", "YOSE", "GRCA"], "group": "NP", "why": "PBS series on the parks; its three most featured parks"},
    {"id": "harriet-film", "stone": "Harriet (film)", "date": "2019-11-01", "kind": "film",
     "units": ["HATU"], "group": "HIST", "why": "Harriet Tubman is its subject"},
]
# Annual known positive (monthly NPS data begin in 1979): run only if the API returns annual or pre-1979 values.
NPS_ANNUAL_MARKS = [
    {"id": "close-encounters", "stone": "Close Encounters of the Third Kind", "date": "1977-11-16", "kind": "film",
     "units": ["DETO"], "group": "NP", "why": "Devils Tower is the film's landing site",
     "known_positive": {"published": False, "sources": ["the park's own history credits the film with a rise in visits"]}},
]

# Comparison units for the exposure gradient (same group, never featured by the stone being tested).
NPS_GROUPS = {
    "BATTLE": ["GETT", "ANTI", "MANA", "VICK", "SHIL", "FRSP", "CHCH", "PETE", "RICH", "STRI", "KEMO", "APCO", "FODO",
               "PERI", "WICR", "MONO", "LIBI", "ANDE", "COWP", "GUCO", "KIMO", "MOCR", "SARA", "MIMA", "VAFO", "COLO",
               "MORR", "FOMC"],
    "HIST": ["ADAM", "EDIS", "ELRO", "FOTH", "HOFR", "LIHO", "SAHI", "SAGA", "THRB", "VAMA", "HOFU", "JOMU", "CARL",
             "FRDO", "BOWA", "GWCA", "EISE", "ANJO", "HSTR", "LYJO", "MALU", "TUIN", "BOAF", "HAGR", "INDE", "STLI",
             "FOSU", "WRBR", "ARHO", "JEFF", "MORU", "LINC", "VIVE", "TUAI", "SEMO", "VALR", "LEWI", "JAZZ"],
    "NP": ["GRCA", "ZION", "BRCA", "ARCH", "CANY", "CARE", "GRTE", "YELL", "GLAC", "ROMO", "YOSE", "SEKI", "OLYM",
           "MORA", "CRLA", "LAVO", "JOTR", "DEVA", "DENA", "KATM", "KEFJ", "GLBA", "MEVE", "PEFO", "BADL", "WICA",
           "THRO", "GUMO", "BIBE", "CAVE", "ACAD", "GRSM", "SHEN", "EVER", "HAVO", "HALE", "REDW", "VOYA", "ISRO"],
}

# Matched control pools for arm B by kind (major US releases of the same kind; arm-B stones of the same kind join).
FILM_POOL = [
    ("Love Story (1970 film)", "1970-12-16"), ("Fiddler on the Roof (film)", "1971-11-03"), ("The Godfather", "1972-03-24"),
    ("American Graffiti", "1973-08-11"), ("The Sting", "1973-12-25"), ("The Exorcist", "1973-12-26"),
    ("Blazing Saddles", "1974-02-07"), ("The Towering Inferno", "1974-12-14"), ("Jaws (film)", "1975-06-20"),
    ("One Flew Over the Cuckoo's Nest (film)", "1975-11-19"), ("Rocky", "1976-11-21"), ("Star Wars (film)", "1977-05-25"),
    ("Smokey and the Bandit", "1977-05-27"), ("Saturday Night Fever", "1977-12-16"), ("Grease (film)", "1978-06-16"),
    ("Animal House", "1978-07-28"), ("Superman (1978 film)", "1978-12-15"), ("Alien (film)", "1979-05-25"),
    ("Moonraker (film)", "1979-06-29"), ("Kramer vs. Kramer", "1979-12-19"), ("The Empire Strikes Back", "1980-05-21"),
    ("9 to 5 (film)", "1980-12-19"), ("Raiders of the Lost Ark", "1981-06-12"), ("E.T. the Extra-Terrestrial", "1982-06-11"),
    ("Tootsie", "1982-12-17"), ("Return of the Jedi", "1983-05-25"), ("Terms of Endearment", "1983-11-23"),
    ("Indiana Jones and the Temple of Doom", "1984-05-23"), ("Ghostbusters", "1984-06-08"), ("Beverly Hills Cop", "1984-12-05"),
    ("Back to the Future", "1985-07-03"), ("Top Gun", "1986-05-16"), ("Crocodile Dundee", "1986-09-26"),
    ("Three Men and a Baby", "1987-11-25"), ("Fatal Attraction", "1987-09-18"), ("Rain Man", "1988-12-16"),
    ("Who Framed Roger Rabbit", "1988-06-22"), ("Batman (1989 film)", "1989-06-23"),
    ("Indiana Jones and the Last Crusade", "1989-05-24"), ("Home Alone", "1990-11-16"), ("Ghost (1990 film)", "1990-07-13"),
    ("Terminator 2: Judgment Day", "1991-07-03"), ("Robin Hood: Prince of Thieves", "1991-06-14"),
    ("Aladdin (1992 Disney film)", "1992-11-11"), ("Home Alone 2: Lost in New York", "1992-11-20"),
    ("Jurassic Park (film)", "1993-06-11"), ("Mrs. Doubtfire", "1993-11-24"), ("Forrest Gump", "1994-07-06"),
    ("The Lion King", "1994-06-15"), ("Toy Story", "1995-11-22"), ("Batman Forever", "1995-06-16"),
    ("Independence Day (1996 film)", "1996-07-03"), ("Twister (1996 film)", "1996-05-10"), ("Titanic (1997 film)", "1997-12-19"),
    ("Men in Black (1997 film)", "1997-07-02"), ("Saving Private Ryan", "1998-07-24"), ("Armageddon (1998 film)", "1998-07-01"),
    ("Star Wars: Episode I – The Phantom Menace", "1999-05-19"), ("The Sixth Sense", "1999-08-06"),
    ("How the Grinch Stole Christmas (2000 film)", "2000-11-17"), ("Gladiator (2000 film)", "2000-05-05"),
    ("Harry Potter and the Philosopher's Stone (film)", "2001-11-16"), ("Shrek", "2001-05-18"),
    ("Spider-Man (2002 film)", "2002-05-03"), ("The Lord of the Rings: The Two Towers", "2002-12-18"),
    ("The Lord of the Rings: The Return of the King", "2003-12-17"), ("Finding Nemo", "2003-05-30"),
    ("Shrek 2", "2004-05-19"), ("Spider-Man 2", "2004-06-30"), ("Star Wars: Episode III – Revenge of the Sith", "2005-05-19"),
    ("The Chronicles of Narnia: The Lion, the Witch and the Wardrobe", "2005-12-09"),
    ("Pirates of the Caribbean: Dead Man's Chest", "2006-07-07"), ("Night at the Museum", "2006-12-22"),
    ("Spider-Man 3", "2007-05-04"), ("Shrek the Third", "2007-05-18"), ("The Dark Knight", "2008-07-18"),
    ("Iron Man (2008 film)", "2008-05-02"), ("Avatar (2009 film)", "2009-12-18"),
    ("Transformers: Revenge of the Fallen", "2009-06-24"), ("Toy Story 3", "2010-06-18"),
    ("Alice in Wonderland (2010 film)", "2010-03-05"), ("Harry Potter and the Deathly Hallows – Part 2", "2011-07-15"),
    ("Transformers: Dark of the Moon", "2011-06-29"), ("The Avengers (2012 film)", "2012-05-04"),
    ("The Dark Knight Rises", "2012-07-20"), ("The Hunger Games: Catching Fire", "2013-11-22"), ("Iron Man 3", "2013-05-03"),
    ("American Sniper", "2014-12-25"), ("Guardians of the Galaxy (film)", "2014-08-01"),
    ("Star Wars: The Force Awakens", "2015-12-18"), ("Jurassic World", "2015-06-12"), ("Rogue One", "2016-12-16"),
    ("Finding Dory", "2016-06-17"), ("Star Wars: The Last Jedi", "2017-12-15"), ("Beauty and the Beast (2017 film)", "2017-03-17"),
    ("Black Panther (film)", "2018-02-16"), ("Avengers: Infinity War", "2018-04-27"), ("Avengers: Endgame", "2019-04-26"),
    ("The Lion King (2019 film)", "2019-07-19"),
]
DOC_POOL = [
    ("Baseball (TV series)", "1994-09-18"), ("The West (miniseries)", "1996-09-15"), ("Frank Lloyd Wright (film)", "1998-11-10"),
    ("Not for Ourselves Alone", "1999-11-07"), ("Mark Twain (2001 film)", "2002-01-14"), ("Horatio's Drive", "2003-10-06"),
    ("Unforgivable Blackness", "2005-01-17"), ("Baseball: The Tenth Inning", "2010-09-28"), ("Prohibition (miniseries)", "2011-10-02"),
    ("The Dust Bowl (miniseries)", "2012-11-18"), ("Jackie Robinson (miniseries)", "2016-04-11"), ("Country Music (miniseries)", "2019-09-15"),
    ("Hoop Dreams", "1994-10-14"), ("Bowling for Columbine", "2002-10-11"), ("Super Size Me", "2004-05-07"),
    ("Fahrenheit 9/11", "2004-06-25"), ("March of the Penguins", "2005-06-24"), ("An Inconvenient Truth", "2006-05-24"),
    ("Planet Earth (2006 TV series)", "2007-03-25"), ("Food, Inc.", "2009-06-12"), ("Waiting for \"Superman\"", "2010-09-24"),
    ("Blackfish (film)", "2013-07-19"), ("Making a Murderer", "2015-12-18"), ("13th (film)", "2016-10-07"),
    ("Won't You Be My Neighbor?", "2018-06-08"), ("RBG (film)", "2018-05-04"), ("Apollo 11 (2019 film)", "2019-03-01"),
    ("Our Planet", "2019-04-05"), ("The Thin Blue Line (1988 film)", "1988-08-26"), ("Roger & Me", "1989-12-20"),
    ("Paris Is Burning (film)", "1991-03-13"), ("Brother's Keeper (1992 film)", "1992-09-09"), ("The War Room", "1993-11-03"),
    ("When We Were Kings", "1996-10-25"), ("Buena Vista Social Club (film)", "1999-06-04"), ("Winged Migration", "2003-04-18"),
    ("Spellbound (2002 film)", "2003-04-30"), ("Man on Wire", "2008-07-25"), ("Exit Through the Gift Shop", "2010-04-16"),
    ("Searching for Sugar Man", "2012-07-27"), ("Citizenfour", "2014-10-24"), ("Amy (2015 film)", "2015-07-03"),
]
TV_POOL = [
    ("Lonesome Dove (miniseries)", "1989-02-05"), ("Seinfeld", "1989-07-05"), ("The Simpsons", "1989-12-17"),
    ("Twin Peaks", "1990-04-08"), ("Northern Exposure", "1990-07-12"), ("Beverly Hills, 90210", "1990-10-04"),
    ("Home Improvement (TV series)", "1991-09-17"), ("Melrose Place", "1992-07-08"), ("The X-Files", "1993-09-10"),
    ("NYPD Blue", "1993-09-21"), ("Frasier", "1993-09-16"), ("ER (TV series)", "1994-09-19"), ("Friends", "1994-09-22"),
    ("Everybody Loves Raymond", "1996-09-13"), ("Ally McBeal", "1997-09-08"), ("Sex and the City", "1998-06-06"),
    ("Will & Grace", "1998-09-21"), ("The Sopranos", "1999-01-10"), ("The West Wing", "1999-09-22"),
    ("Survivor (American TV series)", "2000-05-31"), ("CSI: Crime Scene Investigation", "2000-10-06"),
    ("24 (TV series)", "2001-11-06"), ("American Idol", "2002-06-11"), ("The Wire", "2002-06-02"),
    ("Desperate Housewives", "2004-10-03"), ("Lost (2004 TV series)", "2004-09-22"), ("Grey's Anatomy", "2005-03-27"),
    ("The Office (American TV series)", "2005-03-24"), ("Dexter (TV series)", "2006-10-01"), ("Mad Men", "2007-07-19"),
    ("The Big Bang Theory", "2007-09-24"), ("Breaking Bad", "2008-01-20"), ("Glee (TV series)", "2009-05-19"),
    ("Modern Family", "2009-09-23"), ("The Walking Dead (TV series)", "2010-10-31"), ("Downton Abbey", "2011-01-09"),
    ("Game of Thrones", "2011-04-17"), ("House of Cards (American TV series)", "2013-02-01"),
    ("Orange Is the New Black", "2013-07-11"), ("True Detective", "2014-01-12"), ("Westworld (TV series)", "2016-10-02"),
    ("This Is Us", "2016-09-20"), ("The Crown (TV series)", "2016-11-04"), ("The Handmaid's Tale (TV series)", "2017-04-26"),
    ("Succession (TV series)", "2018-06-03"), ("Chernobyl (miniseries)", "2019-05-06"), ("The Mandalorian", "2019-11-12"),
]
STAGE_POOL = [
    ("Rent (musical)", "1996-04-29"), ("The Lion King (musical)", "1997-11-13"), ("The Producers (musical)", "2001-04-19"),
    ("Mamma Mia! (musical)", "2001-10-18"), ("Avenue Q", "2003-07-31"), ("Wicked (musical)", "2003-10-30"),
    ("Jersey Boys", "2005-11-06"), ("Spring Awakening (musical)", "2006-12-10"), ("In the Heights", "2008-03-09"),
    ("Memphis (musical)", "2009-10-19"), ("The Book of Mormon (musical)", "2011-03-24"), ("Once (musical)", "2012-03-18"),
    ("Kinky Boots (musical)", "2013-04-04"), ("Matilda the Musical", "2013-04-11"), ("Beautiful: The Carole King Musical", "2014-01-12"),
    ("Aladdin (musical)", "2014-03-20"), ("Fun Home (musical)", "2015-04-19"), ("Dear Evan Hansen", "2016-12-04"),
    ("Come from Away", "2017-03-12"), ("The Band's Visit (musical)", "2017-11-09"), ("Frozen (musical)", "2018-03-22"),
    ("Mean Girls (musical)", "2018-04-08"), ("Hadestown", "2019-04-17"),
]
POOLS = {"film": FILM_POOL, "documentary": DOC_POOL, "tv": TV_POOL, "stage": STAGE_POOL,
         "teen_tv": TEEN_TV, "celebrity_death": CELEB_DEATHS}

N_CONTROLS = 19        # nearest controls of the same kind; at least 9 are needed to reach p <= .1
MIN_CONTROLS = 9
