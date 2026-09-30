import Foundation

// What to Eat: cuisines, dishes worth ordering, and the words that give a
// restaurant's cuisine away in its name (saved places only carry the
// category "restaurant", so the name is the one clue we have).

public enum CravingTag: String, Codable, CaseIterable, Sendable {
    case comfort, light, spicy, healthy, vegetarian, cheap, splurge

    public var label: String {
        switch self {
        case .comfort: return "Comfort"
        case .light: return "Light"
        case .spicy: return "Spicy"
        case .healthy: return "Healthy"
        case .vegetarian: return "Veggie"
        case .cheap: return "Cheap eats"
        case .splurge: return "Treat yourself"
        }
    }

    public var emoji: String {
        switch self {
        case .comfort: return "🛋️"
        case .light: return "🥗"
        case .spicy: return "🌶️"
        case .healthy: return "💪"
        case .vegetarian: return "🥦"
        case .cheap: return "💵"
        case .splurge: return "✨"
        }
    }
}

public struct Dish: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let tags: Set<CravingTag>

    public init(_ name: String, _ tags: Set<CravingTag>) {
        self.name = name
        self.tags = tags
    }
}

public struct Cuisine: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let emoji: String
    public let keywords: [String]
    public let dishes: [Dish]

    public init(_ id: String, _ name: String, _ emoji: String, keywords: [String], dishes: [Dish]) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.keywords = keywords
        self.dishes = dishes
    }
}

private typealias D = Dish

public enum CravingLibrary {
    public static let all: [Cuisine] = [
        Cuisine("mexican", "Mexican", "🌮", keywords: ["taco", "tacos", "taqueria", "cantina", "mexican", "burrito", "tex-mex", "cocina", "tequila", "salsa", "agave", "mexicana", "mexico"], dishes: [
            D("Street tacos al pastor", [.cheap, .spicy, .comfort]), D("Chicken burrito bowl", [.healthy, .cheap]),
            D("Enchiladas verdes", [.comfort, .spicy]), D("Carne asada plate", [.comfort]),
            D("Veggie quesadilla", [.vegetarian, .cheap, .comfort]), D("Shrimp ceviche", [.light, .healthy]),
            D("Birria tacos with consommé", [.comfort, .spicy])]),
        Cuisine("italian", "Italian", "🍝", keywords: ["italian", "trattoria", "osteria", "pasta", "ristorante", "cucina", "italia", "vino", "enoteca"], dishes: [
            D("Spaghetti carbonara", [.comfort]), D("Chicken parmesan", [.comfort]),
            D("Margherita pizza", [.vegetarian, .cheap, .comfort]), D("Cacio e pepe", [.vegetarian, .comfort]),
            D("Burrata and tomato salad", [.light, .vegetarian]), D("Osso buco", [.splurge, .comfort]),
            D("Penne arrabbiata", [.vegetarian, .spicy])]),
        Cuisine("pizza", "Pizza", "🍕", keywords: ["pizza", "pizzeria", "pie", "slice"], dishes: [
            D("Pepperoni pie", [.comfort, .cheap]), D("White pizza with ricotta", [.vegetarian, .comfort]),
            D("Buffalo chicken pizza", [.spicy, .comfort]), D("Veggie supreme", [.vegetarian]),
            D("Hot honey soppressata", [.spicy, .comfort]), D("Detroit-style square", [.comfort])]),
        Cuisine("sushi", "Sushi & Japanese", "🍣", keywords: ["sushi", "japanese", "izakaya", "sake", "hibachi", "teppanyaki", "omakase", "ramen", "tokyo", "kyoto", "o ku"], dishes: [
            D("Spicy tuna roll", [.spicy, .light]), D("Salmon nigiri", [.light, .healthy]),
            D("Tonkotsu ramen", [.comfort]), D("Chicken katsu curry", [.comfort]),
            D("Omakase", [.splurge]), D("Vegetable tempura", [.vegetarian]),
            D("Poke-style chirashi bowl", [.healthy, .light])]),
        Cuisine("chinese", "Chinese", "🥡", keywords: ["chinese", "szechuan", "sichuan", "dim sum", "dumpling", "wok", "panda", "china", "peking", "hunan", "canton"], dishes: [
            D("General Tso's chicken", [.comfort]), D("Dan dan noodles", [.spicy, .comfort]),
            D("Soup dumplings", [.comfort]), D("Kung pao chicken", [.spicy]),
            D("Mapo tofu", [.spicy, .vegetarian]), D("Beef and broccoli", [.healthy]),
            D("Vegetable lo mein", [.vegetarian, .cheap])]),
        Cuisine("thai", "Thai", "🍜", keywords: ["thai", "siam", "bangkok", "pad", "basil", "lemongrass"], dishes: [
            D("Pad thai", [.comfort]), D("Pad see ew", [.comfort]),
            D("Green curry", [.spicy]), D("Drunken noodles", [.spicy, .comfort]),
            D("Tom yum soup", [.spicy, .light]), D("Papaya salad", [.light, .healthy, .spicy]),
            D("Massaman curry", [.comfort])]),
        Cuisine("vietnamese", "Vietnamese", "🍲", keywords: ["pho", "vietnamese", "banh", "saigon", "hanoi", "viet"], dishes: [
            D("Beef pho", [.comfort, .healthy]), D("Banh mi", [.cheap]),
            D("Vermicelli bowl with lemongrass pork", [.light, .healthy]), D("Fresh spring rolls", [.light, .healthy]),
            D("Tofu pho", [.vegetarian, .healthy]), D("Broken rice with grilled pork", [.comfort])]),
        Cuisine("indian", "Indian", "🍛", keywords: ["indian", "india", "curry", "tandoor", "tandoori", "masala", "tikka", "biryani", "bombay", "delhi", "mumbai", "punjab", "naan"], dishes: [
            D("Chicken tikka masala", [.comfort]), D("Butter chicken", [.comfort]),
            D("Chana masala", [.vegetarian, .healthy]), D("Lamb vindaloo", [.spicy]),
            D("Palak paneer", [.vegetarian]), D("Chicken biryani", [.comfort, .spicy]),
            D("Tandoori chicken", [.healthy])]),
        Cuisine("korean", "Korean", "🥘", keywords: ["korean", "seoul", "korean bbq", "bibimbap", "kimchi", "gogi"], dishes: [
            D("Bibimbap", [.healthy]), D("Korean fried chicken", [.comfort, .spicy]),
            D("Bulgogi", [.comfort]), D("Kimchi jjigae", [.spicy, .comfort]),
            D("Japchae", [.vegetarian]), D("Korean BBQ for the table", [.splurge])]),
        Cuisine("mediterranean", "Mediterranean & Greek", "🥙", keywords: ["greek", "mediterranean", "gyro", "falafel", "kebab", "shawarma", "hummus", "pita", "lebanese", "ilios", "hellenic", "opa", "cava"], dishes: [
            D("Chicken gyro", [.cheap, .comfort]), D("Falafel plate", [.vegetarian, .healthy]),
            D("Lamb souvlaki", [.healthy]), D("Greek salad with salmon", [.light, .healthy]),
            D("Chicken shawarma bowl", [.healthy]), D("Spanakopita", [.vegetarian])]),
        Cuisine("burgers", "Burgers", "🍔", keywords: ["burger", "burgers", "five guys", "smashburger", "patty", "shake shack"], dishes: [
            D("Classic cheeseburger", [.comfort, .cheap]), D("Smash burger with fries", [.comfort, .cheap]),
            D("Bacon jalapeño burger", [.spicy, .comfort]), D("Veggie burger", [.vegetarian]),
            D("Wagyu burger", [.splurge]), D("Lettuce-wrap burger", [.light, .healthy])]),
        Cuisine("bbq", "BBQ", "🍖", keywords: ["bbq", "barbecue", "bar-b-q", "smokehouse", "smoke", "brisket"], dishes: [
            D("Brisket plate", [.comfort]), D("Pulled pork sandwich", [.comfort, .cheap]),
            D("Baby back ribs", [.comfort, .splurge]), D("Smoked chicken with slaw", [.healthy]),
            D("Burnt ends", [.comfort])]),
        Cuisine("seafood", "Seafood", "🦞", keywords: ["seafood", "fish", "oyster", "crab", "lobster", "shrimp", "clam", "raw bar", "shipwreck", "harbor", "dock", "boat"], dishes: [
            D("Fish tacos", [.light, .cheap]), D("Lobster roll", [.splurge]),
            D("Grilled salmon", [.healthy, .light]), D("Fish and chips", [.comfort]),
            D("Shrimp and grits", [.comfort]), D("Dozen oysters", [.splurge, .light])]),
        Cuisine("steakhouse", "Steakhouse", "🥩", keywords: ["steak", "steakhouse", "chophouse", "butcher", "capital grille"], dishes: [
            D("Ribeye", [.splurge, .comfort]), D("Filet mignon", [.splurge]),
            D("Steak frites", [.comfort]), D("Wedge salad and a sirloin", [.light]),
            D("Surf and turf", [.splurge])]),
        Cuisine("southern", "Southern & Soul", "🍗", keywords: ["southern", "soul food", "biscuit", "biscuits", "cajun", "creole", "hot chicken"], dishes: [
            D("Fried chicken and waffles", [.comfort]), D("Shrimp and grits", [.comfort]),
            D("Nashville hot chicken", [.spicy, .comfort]), D("Meat and three", [.comfort, .cheap]),
            D("Jambalaya", [.spicy, .comfort]), D("Veggie plate with mac and cheese", [.vegetarian, .comfort])]),
        Cuisine("breakfast", "Breakfast & Brunch", "🥞", keywords: ["breakfast", "brunch", "pancake", "waffle", "eggs", "diner", "sunshine", "morning", "first watch", "bagel"], dishes: [
            D("Pancake stack", [.comfort, .cheap]), D("Avocado toast with eggs", [.healthy, .vegetarian]),
            D("Chicken and waffles", [.comfort]), D("Eggs Benedict", [.comfort]),
            D("Breakfast burrito", [.cheap, .comfort]), D("Yogurt parfait", [.light, .vegetarian])]),
        Cuisine("salads", "Salads & Bowls", "🥗", keywords: ["salad", "salads", "bowl", "bowls", "sweetgreen", "chopt", "poke"], dishes: [
            D("Harvest bowl", [.healthy, .light]), D("Chicken Caesar", [.light]),
            D("Cobb salad", [.healthy]), D("Grain bowl with falafel", [.vegetarian, .healthy]),
            D("Poke bowl", [.healthy, .light])]),
        Cuisine("sandwiches", "Sandwiches & Deli", "🥪", keywords: ["deli", "sandwich", "sandwiches", "subs", "hoagie", "jersey mikes", "panera"], dishes: [
            D("Italian sub", [.comfort, .cheap]), D("Turkey club", [.cheap]),
            D("Reuben", [.comfort]), D("Caprese panini", [.vegetarian]),
            D("Chicken salad croissant", [.light])]),
        Cuisine("wings", "Wings & Pub", "🍺", keywords: ["wings", "wing", "pub", "tavern", "tap house", "taphouse", "sports bar", "alehouse", "brewery", "brewing"], dishes: [
            D("Buffalo wings", [.spicy, .comfort]), D("Garlic parmesan wings", [.comfort]),
            D("Loaded nachos", [.comfort, .cheap]), D("Fish and chips", [.comfort]),
            D("Pub burger", [.comfort])]),
        Cuisine("caribbean", "Caribbean", "🌴", keywords: ["caribbean", "jamaican", "jerk", "cuban", "island", "puerto", "haitian"], dishes: [
            D("Jerk chicken with rice and peas", [.spicy, .comfort]), D("Cuban sandwich", [.comfort, .cheap]),
            D("Oxtail stew", [.comfort, .splurge]), D("Ropa vieja", [.comfort]),
            D("Plantains and black beans", [.vegetarian, .cheap])]),
    ]

    public static func cuisine(id: String) -> Cuisine? { all.first { $0.id == id } }
}
