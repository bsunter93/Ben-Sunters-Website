# build a blind panel batch from consolidated candidates plus fresh planted controls; five shuffles
import json, random, sys, os
D = os.path.dirname(os.path.abspath(__file__)) + '/'
cands = json.load(open(D + 'candidates.json'))
obvious = [("Frozen (2013)", "strong sales of Elsa dolls and costumes", "Elsa costumes and dolls sold out across the US during the 2014 holiday season."),
 ("The Beatles on The Ed Sullivan Show (1964)", "a surge of interest in the Beatles in America", "Beatles records topped the US charts in the weeks after the broadcast."),
 ("Pearl Harbor attack (1941)", "the United States entering World War II", "Congress declared war on Japan the day after the attack."),
 ("Fukushima nuclear disaster (2011)", "Japan shutting down its nuclear reactors for safety reviews", "All of Japan's reactors were taken offline for inspections after the accident."),
 ("The iPhone launch (2007)", "a rise in smartphone ownership", "Smartphone ownership grew rapidly in the years after the iPhone's release."),
 ("Hurricane Sandy (2012)", "federal disaster relief funding for New York and New Jersey", "Congress passed the Sandy relief bill in January 2013."),
 ("The Lion King (1994)", "a Broadway musical adaptation of The Lion King", "Disney opened The Lion King musical on Broadway in 1997."),
 ("The Columbine shooting (1999)", "new school security measures", "Many schools added security staff and lockdown drills after the shooting."),
 ("The 1969 Moon landing", "a surge of public interest in space", "Television audiences for the landing were among the largest ever recorded."),
 ("Pokemon Red and Blue (1996)", "a Pokemon animated TV series", "The Pokemon anime premiered in Japan in 1997.")]
fake = [("The Big Bang Theory", "a federal grant program for physics graduate students in 2012", "The 2012 Scientific Workforce Act, nicknamed the Sheldon Act by its sponsors, created graduate fellowships after the show raised interest in physics."),
 ("Shrek (2001)", "Scotland's 2004 ogre-themed tourism law", "The Scottish Parliament passed a tourism marketing act in 2004 that cited Shrek's popularity with visitors."),
 ("Angry Birds", "a Finnish law protecting urban bird nests", "Finland's 2012 Urban Nesting Act was introduced after the game made bird protection a national talking point."),
 ("Mamma Mia! (2008)", "Greece's 2010 island film-permit statute", "Greek lawmakers passed a film permit law in 2010, crediting Mamma Mia! with a rise in production requests."),
 ("Tetris", "a Soviet computing ministry reorganization in 1987", "The Soviet Union reorganized its computing ministry in 1987 after Tetris drew attention to software exports."),
 ("The Crown", "a UK rule requiring disclaimers on royal dramas", "Ofcom introduced a rule in 2021 requiring fiction disclaimers on dramas about the royal family after The Crown."),
 ("Wordle", "a US Department of Education vocabulary initiative in 2022", "The Department of Education launched a five-letter vocabulary program in 2022, citing the game's popularity."),
 ("Ted Lasso", "a UK Football Association coaching kindness charter", "The FA adopted a kindness charter for youth coaches in 2022 after the show."),
 ("Toy Story 3 (2010)", "a California law on donating used toys", "California's 2011 Toy Donation Act was introduced after the film's ending moved lawmakers."),
 ("Yellowstone (TV series)", "a Montana ranchland preservation tax credit", "Montana created a ranch preservation tax credit in 2021, with sponsors citing the series.")]
items, key = [], {}
for c in cands:
    items.append({"stone": c["stone"], "claim": f'{c["stone"]} led to: {c["mark"]}', "evidence": c["sentence"][:420]}); key[len(items) - 1] = ["candidate", c["cid"]]
for a, b, e in obvious: items.append({"stone": a, "claim": f"{a} led to: {b}", "evidence": e}); key[len(items) - 1] = ["planted_obvious", a]
for a, b, e in fake: items.append({"stone": a, "claim": f"{a} led to: {b}", "evidence": e}); key[len(items) - 1] = ["planted_fabricated", a]
for i, it in enumerate(items): it["id"] = f"Q{i:03d}"
json.dump({f"Q{i:03d}": v for i, v in key.items()}, open(D + 'key.json', 'w'), indent=1)
for r in range(1, 6):
    rr = items[:]; random.Random(500 + r).shuffle(rr); json.dump(rr, open(D + f'items_r{r}.json', 'w'), indent=1, ensure_ascii=False)
print(len(items))
