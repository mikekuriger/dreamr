// data/dream_symbols.dart
//
// Curated dictionary of classic dream symbols. Each entry carries:
//  - name:    canonical display name
//  - icon:    a single emoji to render in the symbols grid
//  - meaning: short interpretation shown when the user taps the tile
//  - keywords: lowercase tokens we look for in dream text. Matching is
//              substring-based, so "water" will match "waters" and "watery"
//              but not "underwater" unless we list it explicitly.
//
// Keep this list curated, not exhaustive. Quality > coverage. If a symbol
// fires on almost every dream it stops being a signal.

class DreamSymbolDef {
  final String name;
  final String icon;
  final String meaning;
  final List<String> keywords;

  const DreamSymbolDef({
    required this.name,
    required this.icon,
    required this.meaning,
    required this.keywords,
  });
}

const List<DreamSymbolDef> kDreamSymbols = [
  DreamSymbolDef(
    name: 'Water',
    icon: '🌊',
    meaning:
        'Water often mirrors the emotional state of the dreamer. Calm water can suggest peace; rough or rising water can signal feelings you are working to contain.',
    keywords: ['water', 'ocean', 'sea', 'river', 'lake', 'flood', 'wave', 'tide', 'rain', 'pond'],
  ),
  DreamSymbolDef(
    name: 'Falling',
    icon: '🪂',
    meaning:
        'Falling dreams are commonly linked to a loss of control or insecurity about something in waking life that feels unsteady.',
    keywords: ['falling', 'fell', 'plummet', 'dropped', 'tumbling'],
  ),
  DreamSymbolDef(
    name: 'Flying',
    icon: '🕊️',
    meaning:
        'Flying often represents freedom, ambition, or rising above a difficult situation. The ease of the flight can hint at confidence levels.',
    keywords: ['flying', 'flew', 'soaring', 'hovering', 'levitating'],
  ),
  DreamSymbolDef(
    name: 'Chase',
    icon: '🏃',
    meaning:
        'Being chased often points to something you are avoiding in daily life — a feeling, a decision, or a conversation.',
    keywords: ['chasing', 'chased', 'running from', 'pursued', 'pursuing'],
  ),
  DreamSymbolDef(
    name: 'Teeth',
    icon: '🦷',
    meaning:
        'Teeth falling out is one of the most common anxiety symbols, often tied to self-image, communication, or fears of losing power.',
    keywords: ['teeth', 'tooth'],
  ),
  DreamSymbolDef(
    name: 'Snake',
    icon: '🐍',
    meaning:
        'Snakes can represent transformation, hidden fears, or a person in your life whose intentions feel unclear.',
    keywords: ['snake', 'serpent', 'cobra', 'viper'],
  ),
  DreamSymbolDef(
    name: 'Door',
    icon: '🚪',
    meaning:
        'Doors mark transitions. A locked door can mean an opportunity feels out of reach; an open one often signals readiness for change.',
    keywords: ['door', 'doorway', 'gate', 'entrance'],
  ),
  DreamSymbolDef(
    name: 'Stairs',
    icon: '🪜',
    meaning:
        'Stairs typically represent progress. Climbing up can mean growth or effort; descending can mean revisiting the past or going inward.',
    keywords: ['stairs', 'staircase', 'steps', 'ladder', 'climbing'],
  ),
  DreamSymbolDef(
    name: 'House',
    icon: '🏠',
    meaning:
        'A house often stands in for the self. Different rooms can represent different parts of your inner life; unknown rooms hint at unexplored sides of yourself.',
    keywords: ['house', 'home', 'room', 'hallway', 'attic', 'basement'],
  ),
  DreamSymbolDef(
    name: 'Car',
    icon: '🚗',
    meaning:
        'Vehicles represent direction and control in your life. Who is driving — and whether the journey feels smooth — often matters more than the vehicle itself.',
    keywords: ['car', 'driving', 'vehicle', 'truck', 'highway'],
  ),
  DreamSymbolDef(
    name: 'Lost',
    icon: '🧭',
    meaning:
        'Being lost in a dream often reflects uncertainty about a direction in waking life — career, relationship, or identity.',
    keywords: ['lost', "can't find", 'searching for', 'wandering'],
  ),
  DreamSymbolDef(
    name: 'School',
    icon: '🏫',
    meaning:
        'Schools, classrooms, and exams often surface when you feel tested or judged. They can also signal lessons you sense you have not finished learning.',
    keywords: ['school', 'classroom', 'exam', 'test', 'teacher', 'homework'],
  ),
  DreamSymbolDef(
    name: 'Death',
    icon: '⚰️',
    meaning:
        'Death in dreams rarely means literal death. It usually marks the end of a chapter — a habit, role, or relationship that is changing form.',
    keywords: ['death', 'dying', 'dead', 'funeral', 'grave'],
  ),
  DreamSymbolDef(
    name: 'Fire',
    icon: '🔥',
    meaning:
        'Fire can represent passion, anger, destruction, or transformation. Whether you feel warmed or threatened by it tells you which.',
    keywords: ['fire', 'flames', 'burning', 'smoke', 'wildfire'],
  ),
  DreamSymbolDef(
    name: 'Animals',
    icon: '🐾',
    meaning:
        'Animals often embody instinct or a quality you associate with that creature — strength, loyalty, cunning, fear.',
    keywords: ['dog', 'cat', 'bear', 'wolf', 'lion', 'horse', 'bird', 'animal'],
  ),
  DreamSymbolDef(
    name: 'Stranger',
    icon: '👤',
    meaning:
        'Unknown people in dreams often represent unfamiliar parts of yourself, or qualities you are trying to understand in others.',
    keywords: ['stranger', 'unknown person', 'faceless', 'someone i didn\'t know'],
  ),
  DreamSymbolDef(
    name: 'Family',
    icon: '👨‍👩‍👧',
    meaning:
        'Family members in dreams can represent your relationship with them, or qualities you absorbed from them growing up.',
    keywords: ['mother', 'father', 'mom', 'dad', 'sister', 'brother', 'family', 'parent', 'child'],
  ),
  DreamSymbolDef(
    name: 'Naked',
    icon: '🙈',
    meaning:
        'Being naked or exposed in a dream often relates to vulnerability, authenticity, or fear of being judged for who you really are.',
    keywords: ['naked', 'nude', 'undressed', 'exposed'],
  ),
  DreamSymbolDef(
    name: 'Money',
    icon: '💰',
    meaning:
        'Money in dreams is rarely about money. It often points to self-worth, power, or the value you place on something in your life.',
    keywords: ['money', 'cash', 'wallet', 'rich', 'wealth', 'gold'],
  ),
  DreamSymbolDef(
    name: 'Mirror',
    icon: '🪞',
    meaning:
        'Mirrors invite self-reflection. What you see — clear, distorted, or different from yourself — often reflects how you currently see yourself.',
    keywords: ['mirror', 'reflection'],
  ),
  DreamSymbolDef(
    name: 'Night',
    icon: '🌙',
    meaning:
        'Night settings can suggest the unconscious, things hidden, or a period of introspection. The mood of the night matters as much as its presence.',
    keywords: ['night', 'darkness', 'moon', 'stars'],
  ),
  DreamSymbolDef(
    name: 'Sun',
    icon: '☀️',
    meaning:
        'Sun and bright light often signal clarity, hope, or insight breaking through.',
    keywords: ['sun', 'sunlight', 'daylight', 'sunrise', 'sunset'],
  ),
  DreamSymbolDef(
    name: 'Forest',
    icon: '🌲',
    meaning:
        'Forests and woods represent the unknown, the unconscious, or a journey you must navigate without a clear path.',
    keywords: ['forest', 'woods', 'trees', 'jungle'],
  ),
  DreamSymbolDef(
    name: 'Baby',
    icon: '👶',
    meaning:
        'Babies often represent something new in your life — an idea, a relationship, a version of yourself just beginning to take shape.',
    keywords: ['baby', 'infant', 'newborn'],
  ),
  DreamSymbolDef(
    name: 'Phone',
    icon: '📞',
    meaning:
        'Phones in dreams point to communication. A dropped call or unreachable number can mean a connection you feel is breaking down.',
    keywords: ['phone', 'calling', 'call', 'texting', 'message'],
  ),
];
