import Foundation

struct MicronutrientEducation: Equatable, Sendable {
    let overview: String
    let healthRole: String
    let foodSources: [String]
    let sourceURL: String
    let reviewedOn: String
}

enum MicronutrientEducationCatalog {
    static let sourceURL = "https://ods.od.nih.gov/factsheets/list-VitaminsMinerals/"
    static let reviewedOn = "2026-08-19"

    static func education(for code: String) -> MicronutrientEducation? { entries[code] }

    private static func item(_ overview: String, _ role: String, _ foods: [String]) -> MicronutrientEducation {
        MicronutrientEducation(
            overview: overview,
            healthRole: role,
            foodSources: foods,
            sourceURL: sourceURL,
            reviewedOn: reviewedOn
        )
    }

    static let entries: [String: MicronutrientEducation] = [
        "vitamin_a_mcg_rae": item("Vitamin A is a fat-soluble vitamin.", "It supports vision, immune function, growth, and normal cell development.", ["liver", "eggs", "dairy", "carrots", "sweet potatoes", "spinach"]),
        "vitamin_c_mg": item("Vitamin C is a water-soluble vitamin and antioxidant.", "It helps form collagen, supports wound healing and immune function, and improves iron absorption from plant foods.", ["citrus fruit", "bell peppers", "kiwi", "strawberries", "broccoli"]),
        "vitamin_d_mcg": item("Vitamin D is a fat-soluble vitamin.", "It helps the body absorb calcium and supports bones, muscles, nerves, and immune function.", ["salmon", "trout", "fortified milk or plant milk", "egg yolks", "UV-exposed mushrooms"]),
        "vitamin_e_mg": item("Vitamin E is a fat-soluble antioxidant.", "It helps protect cells and supports immune function.", ["nuts", "seeds", "vegetable oils", "spinach", "broccoli"]),
        "vitamin_k_mcg": item("Vitamin K is a fat-soluble vitamin.", "It supports normal blood clotting and proteins involved in bone health.", ["leafy greens", "broccoli", "Brussels sprouts", "vegetable oils"]),
        "thiamin_mg": item("Thiamin, or vitamin B1, is a water-soluble B vitamin.", "It helps convert food into energy and supports normal cell and nerve function.", ["whole or enriched grains", "pork", "beans", "lentils", "seeds"]),
        "riboflavin_mg": item("Riboflavin, or vitamin B2, is a water-soluble B vitamin.", "It helps release energy from food and supports cell growth and function.", ["eggs", "dairy", "lean meats", "almonds", "mushrooms", "fortified grains"]),
        "niacin_mg_ne": item("Niacin, or vitamin B3, is a water-soluble B vitamin.", "It supports energy metabolism and normal cell function.", ["poultry", "beef", "fish", "nuts", "legumes", "enriched grains"]),
        "vitamin_b6_mg": item("Vitamin B6 is a water-soluble vitamin.", "It supports metabolism, brain development, and immune function.", ["poultry", "fish", "potatoes", "chickpeas", "bananas", "fortified cereal"]),
        "folate_mcg_dfe": item("Folate, or vitamin B9, is a water-soluble vitamin.", "It supports DNA formation, cell division, red blood cells, and fetal neural-tube development.", ["leafy greens", "beans and lentils", "asparagus", "oranges", "fortified grains"]),
        "vitamin_b12_mcg": item("Vitamin B12 is a water-soluble vitamin.", "It supports nerve function, red blood cell formation, and DNA production.", ["meat", "fish", "eggs", "dairy", "fortified plant milks or cereals"]),
        "biotin_mcg": item("Biotin, or vitamin B7, is a water-soluble vitamin.", "It helps the body metabolize fats, carbohydrates, and protein.", ["meat", "fish", "eggs", "nuts and seeds", "sweet potatoes"]),
        "pantothenic_acid_mg": item("Pantothenic acid, or vitamin B5, is a water-soluble vitamin.", "It helps convert food into energy and make fatty acids.", ["chicken", "beef", "mushrooms", "avocado", "whole grains"]),
        "calcium_mg": item("Calcium is a mineral stored mostly in bones and teeth.", "It supports bones and teeth, muscle contraction, nerve signaling, and blood-vessel function.", ["dairy", "fortified plant milk", "calcium-set tofu", "sardines or salmon with bones", "kale"]),
        "iron_mg": item("Iron is a mineral used in hemoglobin and other proteins.", "It helps carry oxygen through the body and supports growth and hormone production.", ["red meat", "poultry", "seafood", "beans and lentils", "spinach", "fortified cereal"]),
        "magnesium_mg": item("Magnesium is a mineral involved in many body processes.", "It supports muscles, nerves, blood glucose regulation, blood pressure, bones, proteins, and DNA.", ["legumes", "nuts", "seeds", "whole grains", "leafy greens"]),
        "phosphorus_mg": item("Phosphorus is a mineral found throughout the body.", "It supports bones and teeth, energy production, DNA, and cell membranes.", ["dairy", "meat", "poultry", "fish", "legumes", "nuts", "whole grains"]),
        "iodine_mcg": item("Iodine is a trace mineral used to make thyroid hormones.", "It supports metabolism, growth, and development.", ["iodized salt", "seaweed", "fish", "dairy", "eggs"]),
        "potassium_mg": item("Potassium is an electrolyte and mineral.", "It supports fluid balance, nerve signaling, muscle contraction, and normal heart function.", ["potatoes", "beans", "tomatoes", "bananas", "oranges", "yogurt"]),
        "zinc_mg": item("Zinc is an essential trace mineral.", "It supports immunity, DNA and protein production, wound healing, and taste.", ["oysters", "meat", "poultry", "beans", "nuts", "whole grains", "dairy"]),
        "selenium_mcg": item("Selenium is an essential trace mineral.", "It supports thyroid function, DNA production, reproduction, and antioxidant systems.", ["seafood", "meat", "poultry", "eggs", "dairy", "Brazil nuts"]),
        "copper_mg": item("Copper is an essential trace mineral.", "It supports energy production, connective tissue, blood vessels, nerves, immunity, and iron metabolism.", ["shellfish", "nuts and seeds", "organ meats", "wheat bran", "dark chocolate"]),
        "manganese_mg": item("Manganese is an essential trace mineral.", "It supports energy metabolism, bone formation, and antioxidant systems.", ["whole grains", "nuts", "legumes", "leafy vegetables", "tea"]),
        "chromium_mcg": item("Chromium is a trace mineral whose role in human health is still being studied.", "It may be involved in insulin action and the metabolism of carbohydrates, fats, and protein.", ["meat", "whole grains", "broccoli", "grape juice"]),
        "molybdenum_mcg": item("Molybdenum is an essential trace mineral.", "It helps enzymes process proteins and other compounds.", ["legumes", "whole grains", "nuts", "dairy"]),
        "chloride_mg": item("Chloride is an electrolyte and mineral.", "It supports fluid balance and helps form stomach acid used in digestion.", ["table salt", "seaweed", "tomatoes", "lettuce", "olives"]),
        "sodium_mg": item("Sodium is an electrolyte the body needs in small amounts.", "It supports fluid balance, nerve signals, and muscle function. Most diets provide enough, so Leafy tracks it against a daily limit.", ["table salt", "bread", "cheese", "cured meats", "soups", "sauces"]),
    ]
}
