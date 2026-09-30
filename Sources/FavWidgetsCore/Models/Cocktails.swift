import Foundation

// Make Me a Drink: a bundled library of well-known cocktails. Hand-written
// classic specs (no third-party database, so no licence or network needed).
// Amounts are in ounces unless a unit says otherwise.

public enum SpiritBase: String, Codable, CaseIterable, Sendable {
    case vodka, tequila, mezcal, gin, rum, whiskey, brandy, bubbly, liqueur, zeroProof

    public var label: String {
        switch self {
        case .vodka: return "Vodka"
        case .tequila: return "Tequila"
        case .mezcal: return "Mezcal"
        case .gin: return "Gin"
        case .rum: return "Rum"
        case .whiskey: return "Whiskey"
        case .brandy: return "Brandy"
        case .bubbly: return "Wine & Bubbly"
        case .liqueur: return "Liqueur"
        case .zeroProof: return "Zero-proof"
        }
    }

    public var emoji: String {
        switch self {
        case .vodka: return "🍸"
        case .tequila, .mezcal: return "🌵"
        case .gin: return "🌿"
        case .rum: return "🏝️"
        case .whiskey: return "🥃"
        case .brandy: return "🍷"
        case .bubbly: return "🥂"
        case .liqueur: return "🍊"
        case .zeroProof: return "🧃"
        }
    }
}

public enum CocktailStyle: String, Codable, CaseIterable, Sendable {
    case sour, highball, stirred, tiki, frozen, fizzy, hot, shot, spritz, creamy

    public var label: String {
        switch self {
        case .sour: return "Sour"
        case .highball: return "Highball"
        case .stirred: return "Stirred"
        case .tiki: return "Tiki"
        case .frozen: return "Frozen"
        case .fizzy: return "Fizzy"
        case .hot: return "Hot"
        case .shot: return "Shot"
        case .spritz: return "Spritz"
        case .creamy: return "Creamy"
        }
    }
}

public enum CocktailStrength: String, Codable, Sendable {
    case light, medium, strong
}

public struct CocktailIngredient: Codable, Equatable, Hashable, Sendable {
    public let amount: String
    public let item: String

    public init(_ amount: String, _ item: String) {
        self.amount = amount
        self.item = item
    }

    public var line: String { amount.isEmpty ? item : "\(amount) \(item)" }
}

public struct Cocktail: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let base: SpiritBase
    public let style: CocktailStyle
    public let strength: CocktailStrength
    public let blurb: String
    public let ingredients: [CocktailIngredient]
    public let steps: [String]
    public let glass: String
    public let garnish: String
    public let orderTip: String

    public init(_ id: String, _ name: String, aliases: [String] = [], base: SpiritBase, style: CocktailStyle,
                strength: CocktailStrength, blurb: String, ingredients: [CocktailIngredient], steps: [String],
                glass: String, garnish: String, orderTip: String) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.base = base
        self.style = style
        self.strength = strength
        self.blurb = blurb
        self.ingredients = ingredients
        self.steps = steps
        self.glass = glass
        self.garnish = garnish
        self.orderTip = orderTip
    }
}

private typealias I = CocktailIngredient

public enum CocktailLibrary {
    private static let shakeSour = ["Add everything to a shaker with ice.", "Shake hard for about 12 seconds.", "Strain into the glass."]
    private static let stir = ["Add everything to a mixing glass with ice.", "Stir for about 25 seconds until well chilled.", "Strain into the chilled glass."]
    private static let build = ["Fill the glass with ice.", "Add the spirit and mixers.", "Stir gently and garnish."]

    public static let all: [Cocktail] = [
        // MARK: Whiskey
        Cocktail("manhattan", "Manhattan", base: .whiskey, style: .stirred, strength: .strong,
                 blurb: "Rye, sweet vermouth and bitters: rich, smooth and classic.",
                 ingredients: [I("2", "rye whiskey (or bourbon)"), I("1", "sweet vermouth"), I("2 dashes", "Angostura bitters")],
                 steps: stir, glass: "Coupe or Nick & Nora", garnish: "Brandied cherry",
                 orderTip: "Say rye or bourbon, and \"up\" (no ice) or \"on the rocks\"."),
        Cocktail("old-fashioned", "Old Fashioned", base: .whiskey, style: .stirred, strength: .strong,
                 blurb: "Whiskey, a little sugar and bitters. The original cocktail.",
                 ingredients: [I("2", "bourbon or rye"), I("1 tsp", "simple syrup (or 1 sugar cube)"), I("2 dashes", "Angostura bitters")],
                 steps: ["Stir the syrup and bitters in the glass.", "Add the whiskey and one big ice cube.", "Stir 20 seconds, then express an orange peel over the top."],
                 glass: "Rocks glass", garnish: "Orange peel (cherry optional)",
                 orderTip: "Pick your bourbon if you have a favorite."),
        Cocktail("whiskey-sour", "Whiskey Sour", base: .whiskey, style: .sour, strength: .medium,
                 blurb: "Bright lemon and bourbon, silky with egg white.",
                 ingredients: [I("2", "bourbon"), I("¾", "fresh lemon juice"), I("¾", "simple syrup"), I("1", "egg white (optional)")],
                 steps: ["Shake everything without ice first if using egg white.", "Add ice and shake hard.", "Strain over fresh ice."],
                 glass: "Rocks glass", garnish: "Angostura drops and a cherry",
                 orderTip: "Ask if they make it with egg white for the foamy top."),
        Cocktail("boulevardier", "Boulevardier", base: .whiskey, style: .stirred, strength: .strong,
                 blurb: "A Negroni made with bourbon: bittersweet and warming.",
                 ingredients: [I("1¼", "bourbon"), I("1", "Campari"), I("1", "sweet vermouth")],
                 steps: stir, glass: "Rocks glass or coupe", garnish: "Orange peel",
                 orderTip: "Great if you like Negronis but want something rounder."),
        Cocktail("sazerac", "Sazerac", base: .whiskey, style: .stirred, strength: .strong,
                 blurb: "New Orleans' rye classic with an absinthe rinse.",
                 ingredients: [I("2", "rye whiskey"), I("¼", "simple syrup"), I("3 dashes", "Peychaud's bitters"), I("", "absinthe to rinse")],
                 steps: ["Rinse a chilled rocks glass with absinthe and discard.", "Stir the rye, syrup and bitters with ice.", "Strain into the glass, no ice."],
                 glass: "Rocks glass", garnish: "Lemon peel, expressed and discarded",
                 orderTip: "A bartender's favorite. Order it where they know cocktails."),
        Cocktail("paper-plane", "Paper Plane", base: .whiskey, style: .sour, strength: .medium,
                 blurb: "Equal parts bourbon, Aperol, Amaro Nonino and lemon.",
                 ingredients: [I("¾", "bourbon"), I("¾", "Aperol"), I("¾", "Amaro Nonino"), I("¾", "fresh lemon juice")],
                 steps: shakeSour, glass: "Coupe", garnish: "None (or a tiny paper plane)",
                 orderTip: "A modern classic. Bittersweet, citrusy and easy to love."),
        Cocktail("gold-rush", "Gold Rush", base: .whiskey, style: .sour, strength: .medium,
                 blurb: "Bourbon, honey and lemon. A cozy whiskey sour.",
                 ingredients: [I("2", "bourbon"), I("¾", "honey syrup (2:1 honey and water)"), I("¾", "fresh lemon juice")],
                 steps: shakeSour, glass: "Rocks glass over ice", garnish: "Lemon peel",
                 orderTip: "If they don't list it, ask for a whiskey sour with honey."),
        Cocktail("penicillin", "Penicillin", base: .whiskey, style: .sour, strength: .medium,
                 blurb: "Scotch, honey, ginger and lemon with a smoky float.",
                 ingredients: [I("2", "blended Scotch"), I("¾", "honey-ginger syrup"), I("¾", "fresh lemon juice"), I("¼", "Islay Scotch float")],
                 steps: ["Shake the Scotch, syrup and lemon with ice.", "Strain over fresh ice.", "Float the Islay Scotch on top."],
                 glass: "Rocks glass", garnish: "Candied ginger",
                 orderTip: "Smoky, spicy and soothing, especially on a cold night."),
        Cocktail("mint-julep", "Mint Julep", base: .whiskey, style: .highball, strength: .strong,
                 blurb: "Bourbon, mint and sugar over crushed ice.",
                 ingredients: [I("2½", "bourbon"), I("½", "simple syrup"), I("8", "mint leaves")],
                 steps: ["Gently press the mint with the syrup.", "Add bourbon and pack with crushed ice.", "Stir until the cup frosts; top with more ice."],
                 glass: "Julep cup", garnish: "Big mint bouquet",
                 orderTip: "A Kentucky Derby favorite. Best in summer."),
        Cocktail("irish-coffee", "Irish Coffee", base: .whiskey, style: .hot, strength: .medium,
                 blurb: "Hot coffee, Irish whiskey, brown sugar and cream.",
                 ingredients: [I("1½", "Irish whiskey"), I("4", "hot coffee"), I("½", "brown sugar syrup"), I("", "lightly whipped cream")],
                 steps: ["Warm the mug with hot water, then empty it.", "Add syrup, whiskey and coffee; stir.", "Float the cream over the back of a spoon."],
                 glass: "Irish coffee mug", garnish: "Cream on top",
                 orderTip: "Dessert and a nightcap in one."),
        Cocktail("whiskey-highball", "Whiskey Highball", aliases: ["highball"], base: .whiskey, style: .highball, strength: .light,
                 blurb: "Whiskey and bubbly soda, tall and crisp.",
                 ingredients: [I("1½", "whiskey (Japanese is traditional)"), I("4", "chilled club soda")],
                 steps: build, glass: "Highball glass", garnish: "Lemon twist",
                 orderTip: "Easy-drinking; ask for ginger ale instead of soda if you like it sweeter."),

        // MARK: Gin
        Cocktail("martini", "Martini", aliases: ["gin martini", "dry martini"], base: .gin, style: .stirred, strength: .strong,
                 blurb: "Gin and dry vermouth, ice cold. Timeless.",
                 ingredients: [I("2½", "gin"), I("½", "dry vermouth"), I("1 dash", "orange bitters (optional)")],
                 steps: stir, glass: "Martini glass or coupe", garnish: "Lemon twist or olive",
                 orderTip: "Say gin or vodka, \"dry\" (less vermouth) or \"dirty\" (olive brine), twist or olive."),
        Cocktail("negroni", "Negroni", base: .gin, style: .stirred, strength: .strong,
                 blurb: "Gin, Campari and sweet vermouth: bitter, bold and Italian.",
                 ingredients: [I("1", "gin"), I("1", "Campari"), I("1", "sweet vermouth")],
                 steps: ["Stir everything with ice.", "Strain over a big ice cube."], glass: "Rocks glass", garnish: "Orange peel",
                 orderTip: "Love it? Try a Boulevardier (bourbon) or a Negroni Sbagliato (prosecco)."),
        Cocktail("gin-and-tonic", "Gin & Tonic", aliases: ["g&t", "gin tonic"], base: .gin, style: .highball, strength: .light,
                 blurb: "Crisp gin and tonic over plenty of ice.",
                 ingredients: [I("2", "gin"), I("4", "tonic water")],
                 steps: build, glass: "Highball or copa glass", garnish: "Lime wedge (or cucumber)",
                 orderTip: "Name your gin; Hendrick's with cucumber is a crowd pleaser."),
        Cocktail("gimlet", "Gimlet", base: .gin, style: .sour, strength: .medium,
                 blurb: "Gin and lime, sharp and refreshing.",
                 ingredients: [I("2", "gin"), I("¾", "fresh lime juice"), I("¾", "simple syrup")],
                 steps: shakeSour, glass: "Coupe", garnish: "Lime wheel",
                 orderTip: "Works with vodka too."),
        Cocktail("tom-collins", "Tom Collins", base: .gin, style: .fizzy, strength: .light,
                 blurb: "Gin lemonade with bubbles.",
                 ingredients: [I("2", "gin"), I("1", "fresh lemon juice"), I("¾", "simple syrup"), I("2", "club soda")],
                 steps: ["Shake gin, lemon and syrup with ice.", "Strain into an ice-filled glass.", "Top with soda."],
                 glass: "Collins glass", garnish: "Lemon wheel and cherry",
                 orderTip: "Tall and easy for a sunny afternoon."),
        Cocktail("french-75", "French 75", base: .gin, style: .fizzy, strength: .medium,
                 blurb: "Gin, lemon and Champagne. Celebratory and crisp.",
                 ingredients: [I("1", "gin"), I("½", "fresh lemon juice"), I("½", "simple syrup"), I("3", "Champagne or brut sparkling wine")],
                 steps: ["Shake gin, lemon and syrup with ice.", "Strain into a flute.", "Top with Champagne."],
                 glass: "Champagne flute", garnish: "Lemon twist",
                 orderTip: "Perfect for brunch or a toast."),
        Cocktail("last-word", "Last Word", base: .gin, style: .sour, strength: .strong,
                 blurb: "Equal parts gin, green Chartreuse, maraschino and lime.",
                 ingredients: [I("¾", "gin"), I("¾", "green Chartreuse"), I("¾", "maraschino liqueur"), I("¾", "fresh lime juice")],
                 steps: shakeSour, glass: "Coupe", garnish: "None",
                 orderTip: "Herbal and punchy. For the adventurous."),
        Cocktail("bees-knees", "Bee's Knees", base: .gin, style: .sour, strength: .medium,
                 blurb: "Gin, honey and lemon. Prohibition-era sunshine.",
                 ingredients: [I("2", "gin"), I("¾", "honey syrup"), I("¾", "fresh lemon juice")],
                 steps: shakeSour, glass: "Coupe", garnish: "Lemon twist",
                 orderTip: "Great first gin cocktail."),
        Cocktail("aviation", "Aviation", base: .gin, style: .sour, strength: .medium,
                 blurb: "Gin, maraschino, violet and lemon: floral and pale purple.",
                 ingredients: [I("2", "gin"), I("½", "maraschino liqueur"), I("¼", "crème de violette"), I("¾", "fresh lemon juice")],
                 steps: shakeSour, glass: "Coupe", garnish: "Brandied cherry",
                 orderTip: "Pretty and floral; ask for it where the bar is serious."),
        Cocktail("southside", "Southside", base: .gin, style: .sour, strength: .medium,
                 blurb: "Gin, lime and mint. Like a gin mojito, served up.",
                 ingredients: [I("2", "gin"), I("1", "fresh lime juice"), I("¾", "simple syrup"), I("6", "mint leaves")],
                 steps: shakeSour, glass: "Coupe", garnish: "Mint leaf",
                 orderTip: "Fresh and herbal."),

        // MARK: Vodka
        Cocktail("moscow-mule", "Moscow Mule", aliases: ["mule"], base: .vodka, style: .highball, strength: .light,
                 blurb: "Vodka, lime and spicy ginger beer in a copper mug.",
                 ingredients: [I("2", "vodka"), I("½", "fresh lime juice"), I("4", "ginger beer")],
                 steps: build, glass: "Copper mug", garnish: "Lime wedge and mint",
                 orderTip: "Swap vodka for bourbon (Kentucky Mule) or tequila (Mexican Mule)."),
        Cocktail("cosmopolitan", "Cosmopolitan", aliases: ["cosmo"], base: .vodka, style: .sour, strength: .medium,
                 blurb: "Citrus vodka, Cointreau, cranberry and lime.",
                 ingredients: [I("1½", "citrus vodka"), I("¾", "Cointreau"), I("½", "fresh lime juice"), I("½", "cranberry juice")],
                 steps: shakeSour, glass: "Martini glass", garnish: "Orange twist",
                 orderTip: "Tart, pink and iconic."),
        Cocktail("espresso-martini", "Espresso Martini", base: .vodka, style: .creamy, strength: .medium,
                 blurb: "Vodka, coffee liqueur and fresh espresso, with a foamy top.",
                 ingredients: [I("1½", "vodka"), I("1", "fresh espresso"), I("½", "coffee liqueur"), I("¼", "simple syrup")],
                 steps: ["Shake everything very hard with ice.", "Double-strain into a chilled glass for the foam."],
                 glass: "Coupe or martini glass", garnish: "Three coffee beans",
                 orderTip: "The after-dinner pick-me-up."),
        Cocktail("bloody-mary", "Bloody Mary", base: .vodka, style: .highball, strength: .light,
                 blurb: "Vodka and savory, spicy tomato juice.",
                 ingredients: [I("1½", "vodka"), I("4", "tomato juice"), I("½", "fresh lemon juice"), I("", "Worcestershire, hot sauce, celery salt, horseradish and pepper to taste")],
                 steps: ["Add everything to a glass with ice.", "Roll between two tins (or stir) to mix.", "Garnish generously."],
                 glass: "Pint or highball glass", garnish: "Celery stalk, lemon, olives",
                 orderTip: "Brunch essential; tell them how spicy you like it."),
        Cocktail("lemon-drop", "Lemon Drop", base: .vodka, style: .sour, strength: .medium,
                 blurb: "Vodka, lemon and sugar with a sugared rim.",
                 ingredients: [I("2", "vodka"), I("¾", "fresh lemon juice"), I("½", "triple sec"), I("½", "simple syrup")],
                 steps: ["Sugar the rim of the glass.", "Shake everything with ice.", "Strain into the glass."],
                 glass: "Martini glass", garnish: "Sugar rim, lemon twist",
                 orderTip: "Sweet-tart and easy."),
        Cocktail("vodka-soda", "Vodka Soda", aliases: ["vodka and soda"], base: .vodka, style: .highball, strength: .light,
                 blurb: "Vodka, soda and lime. Clean and light.",
                 ingredients: [I("1½", "vodka"), I("4", "club soda")],
                 steps: build, glass: "Highball glass", garnish: "Lime wedge",
                 orderTip: "Ask for a splash of fresh juice to liven it up."),
        Cocktail("white-russian", "White Russian", base: .vodka, style: .creamy, strength: .medium,
                 blurb: "Vodka, coffee liqueur and cream over ice.",
                 ingredients: [I("1½", "vodka"), I("1", "coffee liqueur"), I("1", "heavy cream")],
                 steps: ["Pour vodka and coffee liqueur over ice.", "Float the cream on top and stir if you like."],
                 glass: "Rocks glass", garnish: "None",
                 orderTip: "Dessert in a glass."),
        Cocktail("sea-breeze", "Sea Breeze", base: .vodka, style: .highball, strength: .light,
                 blurb: "Vodka with cranberry and grapefruit.",
                 ingredients: [I("1½", "vodka"), I("3", "cranberry juice"), I("1", "grapefruit juice")],
                 steps: build, glass: "Highball glass", garnish: "Lime wedge",
                 orderTip: "Beachy and fruity."),

        // MARK: Tequila & Mezcal
        Cocktail("margarita", "Margarita", aliases: ["marg"], base: .tequila, style: .sour, strength: .medium,
                 blurb: "Tequila, lime and orange liqueur, with a salted rim.",
                 ingredients: [I("2", "blanco tequila"), I("1", "fresh lime juice"), I("¾", "Cointreau"), I("¼", "agave syrup (optional)")],
                 steps: ["Salt half the rim.", "Shake everything with ice.", "Strain over fresh ice."],
                 glass: "Rocks glass", garnish: "Lime wheel, salt rim",
                 orderTip: "Ask for it on the rocks with fresh lime, not a mix. Add jalapeño for heat."),
        Cocktail("paloma", "Paloma", base: .tequila, style: .fizzy, strength: .light,
                 blurb: "Tequila and grapefruit soda: Mexico's favorite highball.",
                 ingredients: [I("2", "blanco tequila"), I("½", "fresh lime juice"), I("4", "grapefruit soda"), I("", "pinch of salt")],
                 steps: build, glass: "Highball glass with salt rim", garnish: "Grapefruit wedge",
                 orderTip: "Lighter and fizzier than a margarita."),
        Cocktail("tequila-sunrise", "Tequila Sunrise", base: .tequila, style: .highball, strength: .light,
                 blurb: "Tequila and orange juice with a grenadine sunrise.",
                 ingredients: [I("2", "blanco tequila"), I("4", "orange juice"), I("½", "grenadine")],
                 steps: ["Build tequila and OJ over ice.", "Slowly pour grenadine so it sinks."],
                 glass: "Highball glass", garnish: "Orange slice and cherry",
                 orderTip: "Fruity and photogenic."),
        Cocktail("ranch-water", "Ranch Water", base: .tequila, style: .fizzy, strength: .light,
                 blurb: "Tequila, lime and Topo Chico. West Texas refreshment.",
                 ingredients: [I("2", "blanco tequila"), I("½", "fresh lime juice"), I("", "Topo Chico (or sparkling water) to top")],
                 steps: build, glass: "Highball glass", garnish: "Lime wedge",
                 orderTip: "Low-sugar and super refreshing."),
        Cocktail("spicy-margarita", "Spicy Margarita", base: .tequila, style: .sour, strength: .medium,
                 blurb: "A margarita with muddled jalapeño heat.",
                 ingredients: [I("2", "blanco tequila"), I("1", "fresh lime juice"), I("¾", "agave syrup"), I("2–3", "jalapeño slices")],
                 steps: ["Muddle the jalapeño in the shaker.", "Add the rest with ice and shake.", "Double-strain over fresh ice."],
                 glass: "Rocks glass with Tajín rim", garnish: "Jalapeño wheel",
                 orderTip: "Ask for a Tajín rim."),
        Cocktail("mezcal-negroni", "Mezcal Negroni", base: .mezcal, style: .stirred, strength: .strong,
                 blurb: "A smoky twist on the Negroni.",
                 ingredients: [I("1", "mezcal"), I("1", "Campari"), I("1", "sweet vermouth")],
                 steps: stir, glass: "Rocks glass", garnish: "Orange peel",
                 orderTip: "For Negroni fans who like smoke."),
        Cocktail("naked-and-famous", "Naked and Famous", base: .mezcal, style: .sour, strength: .medium,
                 blurb: "Mezcal, Aperol, yellow Chartreuse and lime.",
                 ingredients: [I("¾", "mezcal"), I("¾", "Aperol"), I("¾", "yellow Chartreuse"), I("¾", "fresh lime juice")],
                 steps: shakeSour, glass: "Coupe", garnish: "None",
                 orderTip: "Smoky, bittersweet and bright."),
        Cocktail("oaxaca-old-fashioned", "Oaxaca Old Fashioned", base: .tequila, style: .stirred, strength: .strong,
                 blurb: "Reposado tequila and mezcal, sweetened with agave.",
                 ingredients: [I("1½", "reposado tequila"), I("½", "mezcal"), I("1 tsp", "agave syrup"), I("2 dashes", "Angostura bitters")],
                 steps: ["Stir everything with ice.", "Strain over a big cube.", "Flame an orange peel over the top."],
                 glass: "Rocks glass", garnish: "Flamed orange peel",
                 orderTip: "An Old Fashioned for tequila lovers."),

        // MARK: Rum
        Cocktail("mojito", "Mojito", base: .rum, style: .fizzy, strength: .light,
                 blurb: "White rum, mint, lime and soda. Cuba's refresher.",
                 ingredients: [I("2", "white rum"), I("1", "fresh lime juice"), I("¾", "simple syrup"), I("8", "mint leaves"), I("2", "club soda")],
                 steps: ["Gently press mint with the syrup.", "Add rum, lime and crushed ice; stir.", "Top with soda."],
                 glass: "Highball glass", garnish: "Mint sprig and lime",
                 orderTip: "Try a fruit version (strawberry, passion fruit) if they offer one."),
        Cocktail("daiquiri", "Daiquiri", base: .rum, style: .sour, strength: .medium,
                 blurb: "Rum, lime and sugar. The real one, shaken, not frozen.",
                 ingredients: [I("2", "white rum"), I("1", "fresh lime juice"), I("¾", "simple syrup")],
                 steps: shakeSour, glass: "Coupe", garnish: "Lime wheel",
                 orderTip: "Ask for a classic shaken daiquiri; bartenders love it."),
        Cocktail("pina-colada", "Piña Colada", aliases: ["pina colada"], base: .rum, style: .frozen, strength: .medium,
                 blurb: "Rum, pineapple and coconut, blended.",
                 ingredients: [I("2", "white rum"), I("3", "pineapple juice"), I("1½", "cream of coconut"), I("½", "fresh lime juice")],
                 steps: ["Blend everything with a cup of ice until smooth.", "Pour into the glass."],
                 glass: "Hurricane glass", garnish: "Pineapple wedge and cherry",
                 orderTip: "Vacation in a glass."),
        Cocktail("mai-tai", "Mai Tai", base: .rum, style: .tiki, strength: .strong,
                 blurb: "Aged rum, lime, orgeat and orange curaçao.",
                 ingredients: [I("2", "aged rum"), I("¾", "fresh lime juice"), I("½", "orange curaçao"), I("½", "orgeat"), I("¼", "simple syrup")],
                 steps: ["Shake with crushed ice.", "Pour everything into the glass.", "Top with more crushed ice."],
                 glass: "Double rocks glass", garnish: "Mint sprig and spent lime shell",
                 orderTip: "The king of tiki drinks."),
        Cocktail("dark-n-stormy", "Dark 'n' Stormy", aliases: ["dark and stormy"], base: .rum, style: .highball, strength: .light,
                 blurb: "Dark rum floated over spicy ginger beer.",
                 ingredients: [I("2", "dark rum"), I("4", "ginger beer"), I("½", "fresh lime juice (optional)")],
                 steps: ["Fill the glass with ice and ginger beer.", "Float the rum on top."],
                 glass: "Highball glass", garnish: "Lime wedge",
                 orderTip: "Bermuda's national drink."),
        Cocktail("painkiller", "Painkiller", base: .rum, style: .tiki, strength: .medium,
                 blurb: "Dark rum, pineapple, orange and coconut with nutmeg.",
                 ingredients: [I("2", "dark rum"), I("4", "pineapple juice"), I("1", "orange juice"), I("1", "cream of coconut")],
                 steps: ["Shake with ice.", "Pour into an ice-filled glass.", "Grate nutmeg on top."],
                 glass: "Tiki mug or hurricane glass", garnish: "Nutmeg and pineapple",
                 orderTip: "Creamy, tropical and easy."),
        Cocktail("rum-punch", "Rum Punch", base: .rum, style: .tiki, strength: .medium,
                 blurb: "Rum, fruit juices and a splash of grenadine.",
                 ingredients: [I("2", "rum"), I("2", "pineapple juice"), I("1", "orange juice"), I("½", "fresh lime juice"), I("¼", "grenadine")],
                 steps: shakeSour, glass: "Highball glass over ice", garnish: "Orange slice and cherry",
                 orderTip: "Great for a group; order a pitcher."),
        Cocktail("hurricane", "Hurricane", base: .rum, style: .tiki, strength: .strong,
                 blurb: "New Orleans' passion fruit rum punch.",
                 ingredients: [I("1", "light rum"), I("1", "dark rum"), I("2", "passion fruit juice"), I("1", "orange juice"), I("½", "fresh lime juice"), I("½", "grenadine")],
                 steps: shakeSour, glass: "Hurricane glass over ice", garnish: "Orange slice and cherry",
                 orderTip: "Stronger than it tastes."),

        // MARK: Brandy
        Cocktail("sidecar", "Sidecar", base: .brandy, style: .sour, strength: .medium,
                 blurb: "Cognac, orange liqueur and lemon with a sugared rim.",
                 ingredients: [I("1½", "Cognac"), I("¾", "Cointreau"), I("¾", "fresh lemon juice")],
                 steps: shakeSour, glass: "Coupe with sugar rim", garnish: "Orange twist",
                 orderTip: "Elegant and tart."),
        Cocktail("vieux-carre", "Vieux Carré", aliases: ["vieux carre"], base: .brandy, style: .stirred, strength: .strong,
                 blurb: "Rye, Cognac, vermouth and Bénédictine. Rich and spiced.",
                 ingredients: [I("¾", "rye whiskey"), I("¾", "Cognac"), I("¾", "sweet vermouth"), I("1 tsp", "Bénédictine"), I("2 dashes", "each Peychaud's and Angostura bitters")],
                 steps: ["Stir everything with ice.", "Strain over fresh ice."], glass: "Rocks glass", garnish: "Lemon twist",
                 orderTip: "A slow sipper for Manhattan fans."),
        Cocktail("brandy-alexander", "Brandy Alexander", base: .brandy, style: .creamy, strength: .medium,
                 blurb: "Cognac, crème de cacao and cream, dusted with nutmeg.",
                 ingredients: [I("1½", "Cognac"), I("1", "crème de cacao"), I("1", "heavy cream")],
                 steps: shakeSour, glass: "Coupe", garnish: "Grated nutmeg",
                 orderTip: "A dessert drink."),

        // MARK: Wine & Bubbly / Liqueur
        Cocktail("aperol-spritz", "Aperol Spritz", aliases: ["spritz"], base: .liqueur, style: .spritz, strength: .light,
                 blurb: "Aperol, prosecco and soda: bittersweet and bubbly.",
                 ingredients: [I("3", "prosecco"), I("2", "Aperol"), I("1", "club soda")],
                 steps: ["Fill a wine glass with ice.", "Add prosecco, then Aperol, then soda.", "Stir once."],
                 glass: "Wine glass", garnish: "Orange slice",
                 orderTip: "Try a Hugo Spritz (elderflower and mint) for something sweeter."),
        Cocktail("negroni-sbagliato", "Negroni Sbagliato", aliases: ["sbagliato"], base: .bubbly, style: .spritz, strength: .light,
                 blurb: "Campari and sweet vermouth topped with prosecco instead of gin.",
                 ingredients: [I("1", "Campari"), I("1", "sweet vermouth"), I("2", "prosecco")],
                 steps: ["Build Campari and vermouth over ice.", "Top with prosecco and stir gently."],
                 glass: "Rocks or wine glass", garnish: "Orange slice",
                 orderTip: "A lighter, bubbly Negroni."),
        Cocktail("mimosa", "Mimosa", base: .bubbly, style: .fizzy, strength: .light,
                 blurb: "Sparkling wine and orange juice.",
                 ingredients: [I("3", "sparkling wine"), I("3", "fresh orange juice")],
                 steps: ["Pour the orange juice into a flute.", "Top slowly with sparkling wine."],
                 glass: "Champagne flute", garnish: "Orange twist",
                 orderTip: "The brunch default."),
        Cocktail("bellini", "Bellini", base: .bubbly, style: .fizzy, strength: .light,
                 blurb: "Prosecco and white peach purée from Venice.",
                 ingredients: [I("2", "white peach purée"), I("4", "prosecco")],
                 steps: ["Add the purée to a flute.", "Top slowly with prosecco and stir gently."],
                 glass: "Champagne flute", garnish: "None",
                 orderTip: "Sweet, fruity and bubbly."),
        Cocktail("sangria", "Sangria", base: .bubbly, style: .highball, strength: .light,
                 blurb: "Red wine, brandy and fruit, chilled.",
                 ingredients: [I("1 bottle", "red wine"), I("3", "brandy"), I("2", "orange liqueur"), I("", "sliced oranges, apples and berries"), I("", "splash of soda")],
                 steps: ["Combine wine, brandy, liqueur and fruit in a pitcher.", "Chill for a few hours.", "Serve over ice with a splash of soda."],
                 glass: "Wine glass", garnish: "Fruit",
                 orderTip: "Order a pitcher for the table."),
        Cocktail("kir-royale", "Kir Royale", base: .bubbly, style: .fizzy, strength: .light,
                 blurb: "Champagne with a splash of crème de cassis.",
                 ingredients: [I("½", "crème de cassis"), I("5", "Champagne")],
                 steps: ["Add cassis to a flute.", "Top with Champagne."],
                 glass: "Champagne flute", garnish: "Blackberry",
                 orderTip: "Elegant and not too sweet."),
        Cocktail("amaretto-sour", "Amaretto Sour", base: .liqueur, style: .sour, strength: .light,
                 blurb: "Almond liqueur, lemon and a touch of bourbon.",
                 ingredients: [I("1½", "amaretto"), I("¾", "cask-strength bourbon"), I("1", "fresh lemon juice"), I("1 tsp", "simple syrup"), I("½", "egg white")],
                 steps: ["Dry shake, then shake with ice.", "Strain over fresh ice."],
                 glass: "Rocks glass", garnish: "Lemon peel and cherry",
                 orderTip: "Sweet, nutty and tart."),
        Cocktail("grasshopper", "Grasshopper", base: .liqueur, style: .creamy, strength: .light,
                 blurb: "Crème de menthe, crème de cacao and cream: a mint chocolate shake.",
                 ingredients: [I("1", "green crème de menthe"), I("1", "white crème de cacao"), I("1", "heavy cream")],
                 steps: shakeSour, glass: "Coupe", garnish: "Chocolate shavings",
                 orderTip: "Dessert time."),

        // MARK: Shots
        Cocktail("lemon-drop-shot", "Lemon Drop Shot", base: .vodka, style: .shot, strength: .medium,
                 blurb: "Citrus vodka and lemon, sugared.",
                 ingredients: [I("1", "citrus vodka"), I("½", "fresh lemon juice"), I("¼", "simple syrup")],
                 steps: ["Shake with ice.", "Strain into a sugar-rimmed shot glass."], glass: "Shot glass", garnish: "Sugar rim",
                 orderTip: "A crowd-pleasing round."),
        Cocktail("green-tea-shot", "Green Tea Shot", base: .whiskey, style: .shot, strength: .medium,
                 blurb: "Irish whiskey, peach schnapps and sour mix. No tea involved.",
                 ingredients: [I("½", "Irish whiskey"), I("½", "peach schnapps"), I("½", "sour mix"), I("", "splash of lemon-lime soda")],
                 steps: ["Shake the first three with ice.", "Strain into a shot glass and top with soda."], glass: "Shot glass", garnish: "None",
                 orderTip: "Friendly and easy for a group round."),

        // MARK: Zero-proof
        Cocktail("nojito", "Virgin Mojito", aliases: ["nojito", "mojito mocktail"], base: .zeroProof, style: .fizzy, strength: .light,
                 blurb: "Mint, lime and soda without the rum.",
                 ingredients: [I("1", "fresh lime juice"), I("¾", "simple syrup"), I("8", "mint leaves"), I("4", "club soda")],
                 steps: ["Gently press mint with syrup.", "Add lime and crushed ice.", "Top with soda."],
                 glass: "Highball glass", garnish: "Mint sprig",
                 orderTip: "Ask for any mojito as a mocktail."),
        Cocktail("shirley-temple", "Shirley Temple", base: .zeroProof, style: .fizzy, strength: .light,
                 blurb: "Ginger ale, grenadine and a cherry.",
                 ingredients: [I("6", "ginger ale"), I("½", "grenadine")],
                 steps: build, glass: "Highball glass", garnish: "Maraschino cherries",
                 orderTip: "Add vodka and it's a Dirty Shirley."),
        Cocktail("arnold-palmer", "Arnold Palmer", base: .zeroProof, style: .highball, strength: .light,
                 blurb: "Half iced tea, half lemonade.",
                 ingredients: [I("4", "iced tea"), I("4", "lemonade")],
                 steps: build, glass: "Highball glass", garnish: "Lemon wheel",
                 orderTip: "Add vodka for a John Daly."),
        Cocktail("virgin-margarita", "Virgin Margarita", aliases: ["margarita mocktail", "mocktail margarita"], base: .zeroProof, style: .sour, strength: .light,
                 blurb: "Lime, orange and agave with a salted rim.",
                 ingredients: [I("1½", "fresh lime juice"), I("1", "fresh orange juice"), I("¾", "agave syrup"), I("2", "sparkling water")],
                 steps: ["Salt the rim.", "Shake the juices and agave with ice.", "Strain over ice and top with sparkling water."],
                 glass: "Rocks glass", garnish: "Lime wheel",
                 orderTip: "Most bars will make any margarita zero-proof."),
        Cocktail("ginger-fizz", "Ginger Lime Fizz", base: .zeroProof, style: .fizzy, strength: .light,
                 blurb: "Spicy ginger beer, lime and mint.",
                 ingredients: [I("5", "ginger beer"), I("½", "fresh lime juice"), I("4", "mint leaves")],
                 steps: build, glass: "Copper mug or highball", garnish: "Lime and mint",
                 orderTip: "Order it as a \"virgin mule\"."),
    ]

    public static func cocktail(id: String) -> Cocktail? { all.first { $0.id == id } }
}
