"""Generates assets/data/waste_knowledge.json (offline knowledge base for the
text / voice 'Ask EcoSort' feature). Edit the table below and re-run."""
import json, pathlib

BIN = {
  "plastic": "Plastics / yellow recycling bin",
  "paper": "Paper & cardboard / blue recycling bin",
  "glass": "Glass bottle bank / green glass bin",
  "metal": "Metals & cans recycling bin",
  "organic": "Compost heap or green / organic waste bin",
  "ewaste": "E-waste drop-off point or electronics retailer take-back",
  "hazardous": "Hazardous waste collection point — never household bins",
}
# name | aliases (comma) | category | handling
ITEMS = """
plastic bottle|water bottle,soda bottle,pet bottle,drink bottle,juice bottle|plastic|Empty it, rinse, squash and put the cap back on.
plastic bag|carrier bag,shopping bag,polythene,kaveera,nylon bag,polythene bag|plastic|Reuse it. Many kerbside bins refuse film — return to supermarket film collection if available.
plastic cup|disposable cup,plastic glass|plastic|Rinse and recycle with plastics.
food wrapper|sweet wrapper,candy wrapper,chip packet,crisp packet,snack wrapper|plastic|Mixed-material film: put in plastics only if accepted locally, otherwise general waste.
plastic container|tub,yoghurt pot,yogurt cup,takeaway container,food container,margarine tub|plastic|Scrape out food, rinse, recycle with plastics.
straw|plastic straw,drinking straw|plastic|Too small to sort — general waste. Switch to reusable straws.
plastic cutlery|plastic fork,plastic spoon,plastic knife|plastic|Usually not recyclable — general waste; prefer reusable cutlery.
jerrycan|jerry can,plastic jerrican|plastic|Rinse well; reuse or recycle with rigid plastics. If it held fuel or chemicals, treat as hazardous.
shampoo bottle|detergent bottle,soap bottle,lotion bottle|plastic|Rinse out and recycle with plastics; remove pumps.
styrofoam|polystyrene,foam box,foam cup,thermocol|plastic|Rarely recycled kerbside — check local drop-off; otherwise general waste.
cardboard box|carton box,shipping box,amazon box,cardboard|paper|Flatten, remove tape, keep dry.
newspaper|news paper,magazine,flyer,leaflet|paper|Keep dry and recycle with paper.
paper|office paper,printer paper,notebook,exercise book,envelope,letter|paper|Recycle with paper; shred sensitive documents first.
book|books,textbook|paper|Donate if usable; otherwise recycle with paper (remove hard covers).
pizza box|greasy box|organic|Greasy parts go to compost; clean lid parts can go with paper.
paper cup|coffee cup,disposable coffee cup|paper|Most have a plastic lining — use a cup recycling point or general waste. Lids go with plastics.
egg carton|egg box,egg tray|paper|Recycle with paper or compost it.
tissue|paper towel,napkin,serviette,kitchen roll|organic|Used tissues can be composted; never in paper recycling.
milk carton|juice carton,tetra pak,tetrapak|paper|Rinse and flatten; recycle where cartons are accepted.
glass bottle|beer bottle,wine bottle,soda glass bottle|glass|Rinse, remove caps (caps go to metal), bottle bank.
glass jar|jam jar,sauce jar,baby food jar|glass|Rinse, remove the metal lid, recycle with glass.
drinking glass|wine glass,broken glass,glass cup|glass|Drinking glass and window glass melt differently — wrap and put in general waste unless your area accepts it.
mirror|window glass,glass pane|glass|Not bottle-bank glass. Wrap safely and take to a recycling centre.
aluminium can|aluminum can,soda can,beer can,drink can,tin can,coke can|metal|Empty, rinse and squash.
food tin|tin,canned food,bean tin,tuna can|metal|Rinse, push the lid inside, recycle with metals.
aluminium foil|aluminum foil,foil,foil tray,silver paper|metal|Clean foil only — scrunch into a ball first.
bottle cap|metal cap,crown cap,metal lid,jar lid|metal|Collect caps in a can, then recycle with metals.
cutlery|fork,spoon,knife,metal spoon|metal|Donate if usable, otherwise scrap metal recycling.
scrap metal|iron sheet,nails,wire,metal pipe,pot,pan,saucepan|metal|Take to a scrap-metal dealer or recycling centre.
aerosol can|spray can,deodorant can,air freshener|hazardous|Only fully empty aerosols go in metal recycling. Partly full ones are hazardous.
banana peel|banana,banana skin,matooke peel,plantain peel|organic|Compost it.
fruit|apple,orange,mango,pineapple,fruit peel,peels,orange peel,apple core|organic|Compost it.
vegetables|vegetable scraps,cabbage,carrot,potato peel,onion skin,salad|organic|Compost it.
food scraps|leftovers,food waste,left over food,rice,bread,meat,bones,fish|organic|Organic bin; meat and bones only if your compost service accepts them.
coffee grounds|tea bags,tea leaves,coffee filter|organic|Compost it — great for soil.
eggshells|egg shell,egg shells|organic|Compost it (crush first).
garden waste|leaves,grass,grass clippings,branches,flowers,twigs,yard waste|organic|Compost or green waste collection.
wood|sawdust,wooden pallet,untreated wood|organic|Untreated wood can be composted or chipped; painted wood goes to a recycling centre.
phone|mobile phone,cell phone,smartphone,cellphone,iphone,android phone|ewaste|Wipe data, remove SIM, take to an e-waste collection point.
laptop|computer,pc,notebook computer,desktop,tablet,ipad|ewaste|Back up and wipe data; e-waste collection or manufacturer take-back.
charger|cable,usb cable,adapter,power cord,earphones,headphones|ewaste|E-waste drop-off; cables are valuable for copper recovery.
remote control|remote,tv remote|ewaste|Remove the batteries (hazardous), then e-waste.
television|tv,monitor,screen|ewaste|E-waste collection — old CRT screens contain lead.
keyboard|computer mouse,mouse,printer,router,speaker|ewaste|E-waste drop-off point.
small appliance|kettle,toaster,iron,hair dryer,blender,microwave,fan,radio|ewaste|E-waste or electrical recycling point.
battery|batteries,aa battery,aaa battery,lithium battery,car battery,button cell,power bank,dry cell|hazardous|Tape the terminals and take to a battery collection point. Never bin — fire risk.
light bulb|bulb,fluorescent tube,cfl,energy saving bulb,tube light|hazardous|Contains mercury — hazardous collection. LED bulbs go to e-waste.
paint|paint tin,paint can,varnish,thinner,solvent|hazardous|Hazardous waste collection; never pour down drains.
chemicals|bleach,pesticide,insecticide,herbicide,acid,cleaning chemicals,rat poison,fertilizer|hazardous|Keep in the original container, lid tight; hazardous collection.
medicine|pills,tablets,expired medicine,drugs,medication,syrup|hazardous|Return to a pharmacy or health centre for safe disposal.
syringe|needle,sharps,injection,lancet|hazardous|Put in a rigid sharps container and return to a health facility.
motor oil|engine oil,used oil,petrol,diesel,fuel,kerosene,paraffin|hazardous|Seal in a container and take to a garage or hazardous collection.
thermometer|mercury thermometer|hazardous|Mercury — hazardous collection. Digital thermometers are e-waste.
gas cylinder|gas canister,lpg cylinder,camping gas|hazardous|Return to the supplier; never crush or burn.
nail polish|nail varnish,nail polish remover,acetone|hazardous|Hazardous collection.
diaper|nappy,diapers,sanitary pad,pads|organic|Not recyclable — wrap and put in general waste (not compost).
"""

out = []
for line in ITEMS.strip().splitlines():
    name, aliases, cat, handling = [x.strip() for x in line.split("|")]
    out.append({"name": name,
                "aliases": [a.strip() for a in aliases.split(",") if a.strip()],
                "category": cat, "handling": handling, "where": BIN[cat]})
# Exceptions where the bin text should differ from the category default.
for o in out:
    if o["name"] == "diaper":
        o["where"] = "General waste bin (wrapped)"
    if o["name"] == "medicine":
        o["where"] = "Pharmacy / health-centre take-back"
p = pathlib.Path(__file__).resolve().parent.parent / "assets/data/waste_knowledge.json"
p.write_text(json.dumps({"bins": BIN, "items": out}, indent=1))
print(f"wrote {len(out)} items to {p}")
