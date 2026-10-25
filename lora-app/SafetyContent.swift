import Foundation

struct SafetyStep: Hashable {
    let title: String
    let detail: String
}

/// All first-aid and emergency guidance lives here, compiled into the app,
/// so it is always available with no internet connection.
/// Based on CDC and National Weather Service heat-illness guidance.
enum SafetyContent {

    // MARK: Heat stroke (life-threatening)

    static let heatStrokeSigns: [String] = [
        "Confusion, slurred speech, agitation, or acting strangely",
        "Passing out, or can't be woken up",
        "A seizure",
        "Very hot skin: red and dry, or still sweaty if they were exercising or working",
        "Body temperature of 103°F (39.4°C) or higher, if you can measure it",
        "Fast, strong pulse, fast breathing, throbbing headache, nausea"
    ]

    static let heatStrokeSteps: [SafetyStep] = [
        SafetyStep(
            title: "Call 911 now",
            detail: "Heat stroke is a life-threatening emergency. Don't wait to see if they get better. Outside the US, call your local emergency number. Put the phone on speaker and follow the dispatcher."),
        SafetyStep(
            title: "Get them out of the heat",
            detail: "Move them to shade or, better, air conditioning. Lay them down and stay with them. Never leave them alone."),
        SafetyStep(
            title: "Remove extra clothing",
            detail: "Take off outer layers, hats, socks and shoes so heat can escape."),
        SafetyStep(
            title: "Cool them down fast",
            detail: "Best: put them in a cold water or ice bath if one is available and they can be kept safe. Otherwise soak their skin and clothes with cool water, and put cold wet cloths or ice packs on the head, neck, armpits and groin. Keep re-wetting."),
        SafetyStep(
            title: "Use a fan only if it helps",
            detail: "Fan them only if the heat index is below the high 90s °F. In very hot, humid air a fan can make things worse, so rely on air conditioning, shade, and cold water or ice."),
        SafetyStep(
            title: "Watch their breathing",
            detail: "If they stop responding and aren't breathing normally, start CPR if you know how, or follow the dispatcher's instructions: push hard and fast in the center of the chest. If they have a seizure, don't put anything in their mouth and move objects away. If they vomit, roll them onto their side."),
        SafetyStep(
            title: "Keep cooling until help arrives",
            detail: "Don't stop when they start to look better. Tell the paramedics what happened, how long they were in the heat, and what you did.")
    ]

    static let heatStrokeDonts: [String] = [
        "Don't give fluids if they are confused, drowsy, vomiting or unconscious. They could choke. If they are fully alert and can swallow, small sips of cool water are okay.",
        "Don't give aspirin, acetaminophen, alcohol or caffeine.",
        "Don't leave them alone, even if they seem better.",
        "Don't wait to see if it passes. Call first."
    ]

    // MARK: Heat exhaustion (serious, can become heat stroke)

    static let heatExhaustionSigns: [String] = [
        "Heavy sweating",
        "Cold, pale, clammy skin",
        "Fast, weak pulse",
        "Nausea or vomiting",
        "Muscle cramps",
        "Tiredness, weakness, dizziness, headache",
        "Fainting"
    ]

    static let heatExhaustionSteps: [String] = [
        "Move them to a cooler place, ideally air conditioning. Have them lie down.",
        "Loosen or remove tight clothing.",
        "Cool them with cool, wet cloths or a cool bath.",
        "Give small sips of cool water. Stop if they feel nauseated.",
        "Get medical help if they vomit, symptoms get worse, or symptoms last longer than an hour.",
        "If they become confused, pass out, or stop sweating, treat it as heat stroke and call 911."
    ]

    // MARK: Prevention

    static let preventionTips: [String] = [
        "Drink water before you feel thirsty. Take regular breaks in shade or air conditioning.",
        "Avoid hard activity in the hottest part of the day.",
        "Wear light, loose clothing and a hat, and use sunscreen.",
        "Never leave children or pets in a parked car, even for a minute.",
        "Check on older adults, young children, and people who work or exercise outdoors.",
        "Some medicines and alcohol raise your risk. Take extra care."
    ]

    static let disclaimer =
        "General first-aid information based on CDC and National Weather Service guidance. It is not medical advice and does not replace emergency care. If you are unsure, call 911."
}
