"""Kaggle datasets used to train the EcoSort 7-class detector, and how each
source class maps onto the app's categories.

  plastic · paper · glass · metal · organic · ewaste · hazardous

Detection needs bounding boxes. TACO provides real boxes ("trash in the
wild"). The classification datasets show one item per photo, so each image
becomes a single box covering the object (see build_dataset.py) — a standard
trick that adds tens of thousands of labelled examples, especially for the
e-waste and hazardous classes that TACO barely covers.
"""

CLASSES = ["plastic", "paper", "glass", "metal", "organic", "ewaste", "hazardous"]

KAGGLE_DATASETS = {
    # slug: (kind, description)
    "kneroma/tacotrashdataset": ("detection", "TACO — 1.5k photos, 4.7k boxes, 60 litter classes"),
    "sumn2u/garbage-classification-v2": ("classification", "~20k images, 10 classes incl. battery"),
    "mostafaabla/garbage-classification": ("classification", "~15k images, 12 classes incl. battery"),
    "joebeachcapital/realwaste": ("classification", "RealWaste — 4.7k landfill photos, 9 classes"),
    "akshat103/e-waste-image-dataset": ("classification", "~3k images, 10 e-waste device types"),
}

# Folder / class name (lower-case) -> category. None = ignore.
CLASSIFICATION_MAP = {
    # garbage-classification(-v2)
    "plastic": "plastic",
    "paper": "paper",
    "cardboard": "paper",
    "glass": "glass",
    "brown-glass": "glass",
    "green-glass": "glass",
    "white-glass": "glass",
    "metal": "metal",
    "biological": "organic",
    "battery": "hazardous",
    "trash": None,
    "clothes": None,
    "shoes": None,
    # RealWaste
    "food organics": "organic",
    "vegetation": "organic",
    "miscellaneous trash": None,
    "textile trash": None,
    # E-waste dataset (all devices -> ewaste, but batteries are hazardous)
    "keyboard": "ewaste",
    "microwave": "ewaste",
    "mobile": "ewaste",
    "mouse": "ewaste",
    "pcb": "ewaste",
    "player": "ewaste",
    "printer": "ewaste",
    "television": "ewaste",
    "washing machine": "ewaste",
}


def taco_to_category(name: str):
    """Maps one of TACO's 60 classes to an EcoSort category (or None)."""
    n = name.lower()
    if any(k in n for k in ("battery", "aerosol")):
        return "hazardous"
    if any(k in n for k in ("glass", "jar")):
        return "glass"
    if any(k in n for k in ("aluminium", "metal", "can", "pop tab", "scrap")):
        # "Food Can", "Drink can", "Metal lid", "Aluminium foil"
        if "carton" not in n:
            return "metal"
    if any(k in n for k in ("food waste",)):
        return "organic"
    if any(k in n for k in ("carton", "paper", "cardboard", "pizza box", "toilet tube", "tissues", "magazine")):
        if "plastified" in n:
            return "plastic"
        return "paper"
    if any(k in n for k in ("plastic", "bottle", "cup", "bag", "wrapper", "film", "straw", "styrofoam",
                            "foam", "crisp", "tub", "tupperware", "container", "lid", "six pack",
                            "squeezable", "blister", "glooves", "utensils")):
        return "plastic"
    return None  # cigarette, shoe, rope, unlabeled litter …
