#!/usr/bin/env python3
"""Generate Donkey task-intent evals for common macOS apps.

The corpus is data-only on purpose. It is meant to exercise the local task
intent model boundary without adding Swift fixtures for every app.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


SUITE_ID = "macos-default-apps-v1"
SOURCE = "macos-default-app-selection-2026-05-21"
OUTPUT_DIR = Path("evals/task-intent")
JSONL_PATH = OUTPUT_DIR / f"{SUITE_ID}.jsonl"
MANIFEST_PATH = OUTPUT_DIR / f"{SUITE_ID}.manifest.json"
CASES_PER_APP = 10

SEARCH_TOOLS = [
    "app.openOrFocus",
    "app.observe",
    "ui.focusSearch",
    "ui.setText",
    "ui.pressReturn",
    "app.verifyCommand",
]
ADDRESS_TOOLS = [
    "app.openOrFocus",
    "app.observe",
    "ui.focusAddressBar",
    "ui.setText",
    "ui.pressReturn",
    "app.verifyCommand",
]
CREATE_TEXT_TOOLS = [
    "app.openOrFocus",
    "app.observe",
    "ui.newDocument",
    "ui.setText",
    "app.verifyCommand",
]
TEXT_ENTRY_TOOLS = [
    "app.openOrFocus",
    "app.observe",
    "ui.focusTextEntry",
    "ui.setText",
    "ui.pressReturn",
    "app.verifyCommand",
]
OPEN_ONLY_TOOLS = ["app.openOrFocus", "app.verifyCommand"]


def app(
    name: str,
    default_class: str,
    category: str,
    tools: list[str],
    cases: list[tuple[str, str | list[str] | None] | dict[str, Any]],
    *,
    bundle_id: str | None = None,
    task_type: str = "local_app_interaction",
) -> dict[str, Any]:
    return {
        "name": name,
        "bundleIdentifier": bundle_id,
        "defaultClass": default_class,
        "category": category,
        "taskType": task_type,
        "requiredTools": tools,
        "cases": cases,
    }


APP_SPECS: list[dict[str, Any]] = [
    app(
        "App Store",
        "macos_default",
        "store_search",
        SEARCH_TOOLS,
        [
            ("find a focused markdown editor in the app store", "markdown editor"),
            ("look up the latest TestFlight app listing", "TestFlight"),
            ("search the app store for a lightweight habit tracker", "habit tracker"),
            ("find an app for scanning receipts", "scanning receipts"),
            ("show me password manager options in the app store", "password manager"),
            ("search for a Pomodoro timer in the app store", "Pomodoro timer"),
            ("find Apple Developer in the app store", "Apple Developer"),
            ("look for a good white noise app", "white noise"),
            ("search app store for a screen ruler", "screen ruler"),
            ("find apps for learning Korean vocabulary", "Korean vocabulary"),
        ],
        bundle_id="com.apple.AppStore",
    ),
    app(
        "Apps",
        "macos_default",
        "system_app_launcher",
        OPEN_ONLY_TOOLS,
        [
            ("open Apps", None),
            ("show my Apps", None),
            ("open the Apps view", None),
            ("bring up Apps so I can find Calculator", None),
            ("show all installed apps", None),
            ("open Apps from the system", None),
            ("show the app launcher", None),
            ("open Apps so I can pick Safari", None),
            ("bring the Apps screen forward", None),
            ("show the system Apps list", None),
        ],
        task_type="app_open",
    ),
    app(
        "Automator",
        "macos_default",
        "automation_creation",
        CREATE_TEXT_TOOLS,
        [
            ("create an automator quick action to resize selected images", "resize selected images"),
            ("start an Automator workflow for renaming files with today's date", "renaming files"),
            ("make an Automator script that turns PDFs into images", "PDFs into images"),
            ("open Automator and draft a folder action for incoming screenshots", "incoming screenshots"),
            ("build an Automator workflow to combine text files", "combine text files"),
            ("set up an Automator quick action for compressing selected files", "compressing selected files"),
            ("create a workflow in Automator that opens my daily apps", "opens my daily apps"),
            ("start a new Automator app that speaks selected text", "speaks selected text"),
            ("make an Automator folder action that tags invoices", "tags invoices"),
            ("draft a workflow in Automator to convert images to jpeg", "convert images to jpeg"),
        ],
        bundle_id="com.apple.Automator",
    ),
    app(
        "Books",
        "macos_default",
        "library_search",
        SEARCH_TOOLS,
        [
            ("search Books for The Design of Everyday Things", "The Design of Everyday Things"),
            ("find my copy of Dune in Books", "Dune"),
            ("look up books about systems thinking", "systems thinking"),
            ("search Apple Books for Korean history", "Korean history"),
            ("find audiobooks by Octavia Butler", "Octavia Butler"),
            ("open Books and search for Swift programming", "Swift programming"),
            ("look for saved PDFs about product strategy in Books", "product strategy"),
            ("search Books for meditation guides", "meditation guides"),
            ("find the book Sapiens", "Sapiens"),
            ("look up books about jazz piano", "jazz piano"),
        ],
        bundle_id="com.apple.iBooksX",
    ),
    app(
        "Calculator",
        "macos_default",
        "calculation",
        TEXT_ENTRY_TOOLS,
        [
            ("calculate 18 percent of 249.50", "18% of 249.50"),
            ("what is 72 divided by 9 in Calculator", "72 / 9"),
            ("open Calculator and compute 14 * 37", "14 * 37"),
            ("use Calculator for 1024 plus 768", "1024 + 768"),
            ("calculate the tip on 86 dollars at 22 percent", "86 * 0.22"),
            ("convert 5 miles to kilometers in Calculator", "5 miles to kilometers"),
            ("figure out 19 squared in Calculator", "19^2"),
            ("calculate 3.5 hours times 125 dollars", "3.5 * 125"),
            ("use Calculator to subtract 47.89 from 120", "120 - 47.89"),
            ("compute 1 divided by 7", "1 / 7"),
        ],
        bundle_id="com.apple.calculator",
    ),
    app(
        "Calendar",
        "macos_default",
        "calendar_search",
        SEARCH_TOOLS,
        [
            ("find my dentist appointment in Calendar", "dentist"),
            ("show calendar events for next Friday's demo", "demo"),
            ("look for my flight to Seoul in Calendar", "Seoul"),
            ("search Calendar for the quarterly planning meeting", "quarterly planning"),
            ("find the next birthday dinner on my calendar", "birthday dinner"),
            ("show me calendar items with Alex this week", "Alex"),
            ("look up the investor call in Calendar", "investor call"),
            ("find the school pickup reminder in Calendar", "school pickup"),
            ("search Calendar for the product review", "product review"),
            ("find events at the dentist office", "dentist office"),
        ],
        bundle_id="com.apple.iCal",
    ),
    app(
        "Chess",
        "macos_default",
        "game_open",
        OPEN_ONLY_TOOLS,
        [
            ("open Chess and start a new game", None),
            ("launch Chess for a quick match", None),
            ("start a computer chess game", None),
            ("bring up Chess so I can practice openings", None),
            ("open Chess in the foreground", None),
            ("start a casual chess session", None),
            ("launch the built in chess app", None),
            ("open Chess and get ready to play black", None),
            ("show Chess for a quick puzzle break", None),
            ("start Chess from the Mac apps", None),
        ],
        bundle_id="com.apple.Chess",
        task_type="app_open",
    ),
    app(
        "Clock",
        "macos_default",
        "time_utility",
        TEXT_ENTRY_TOOLS,
        [
            ("set a 20 minute timer in Clock", "20 minute timer"),
            ("open Clock and create an alarm for 6:45 AM", "6:45 AM"),
            ("start a stopwatch in Clock", "stopwatch"),
            ("set a timer for steeping tea for 4 minutes", "4 minutes"),
            ("show world clock for Seoul", "Seoul"),
            ("make an alarm called gym for 7 AM", "gym 7 AM"),
            ("open Clock and set a 90 minute focus timer", "90 minute focus timer"),
            ("show me the time in London in Clock", "London"),
            ("set a timer for laundry for 45 minutes", "45 minutes"),
            ("create a weekday alarm for 8:10 AM", "weekday 8:10 AM"),
        ],
        bundle_id="com.apple.clock",
    ),
    app(
        "Contacts",
        "macos_default",
        "contact_search",
        SEARCH_TOOLS,
        [
            ("find Priya Shah in Contacts", "Priya Shah"),
            ("look up mom's phone number in Contacts", "mom"),
            ("search Contacts for the plumber", "plumber"),
            ("find Alex Kim's email address", "Alex Kim"),
            ("open Contacts and search for the dentist", "dentist"),
            ("look for our landlord in Contacts", "landlord"),
            ("find contacts at Acme Corp", "Acme Corp"),
            ("search for Jamie's birthday card address", "Jamie"),
            ("find the emergency vet in Contacts", "emergency vet"),
            ("look up Dana from design", "Dana design"),
        ],
        bundle_id="com.apple.AddressBook",
    ),
    app(
        "Dictionary",
        "macos_default",
        "reference_search",
        SEARCH_TOOLS,
        [
            ("define liminal in Dictionary", "liminal"),
            ("look up the word serendipity", "serendipity"),
            ("open Dictionary and search for epistemic", "epistemic"),
            ("find the thesaurus entry for fast", "fast"),
            ("look up the meaning of pareidolia", "pareidolia"),
            ("search Dictionary for recursion", "recursion"),
            ("define affordance", "affordance"),
            ("look up etymology of robot", "robot"),
            ("find synonyms for careful", "careful"),
            ("search Dictionary for gestalt", "gestalt"),
        ],
        bundle_id="com.apple.Dictionary",
    ),
    app(
        "FaceTime",
        "macos_default",
        "call_or_contact",
        SEARCH_TOOLS,
        [
            ("FaceTime Maya", "Maya"),
            ("start a FaceTime call with dad", "dad"),
            ("open FaceTime and call the design team", "design team"),
            ("video call Jordan on FaceTime", "Jordan"),
            ("find Sarah in FaceTime", "Sarah"),
            ("start an audio FaceTime with my brother", "brother"),
            ("call the dentist through FaceTime", "dentist"),
            ("FaceTime our weekly study group", "weekly study group"),
            ("open FaceTime for a call with Alex Kim", "Alex Kim"),
            ("start a video call with mom", "mom"),
        ],
        bundle_id="com.apple.FaceTime",
    ),
    app(
        "Find My",
        "macos_default",
        "device_or_person_search",
        SEARCH_TOOLS,
        [
            ("find my AirPods", "AirPods"),
            ("show where my MacBook is in Find My", "MacBook"),
            ("look up Sam's location in Find My", "Sam"),
            ("find my bike tracker", "bike tracker"),
            ("open Find My and search for wallet", "wallet"),
            ("show my iPad location", "iPad"),
            ("find the keys AirTag", "keys"),
            ("look for my luggage tracker", "luggage tracker"),
            ("show Find My for mom's phone", "mom phone"),
            ("locate my work backpack", "work backpack"),
        ],
        bundle_id="com.apple.findmy",
    ),
    app(
        "Font Book",
        "macos_default",
        "font_search",
        SEARCH_TOOLS,
        [
            ("find Helvetica Neue in Font Book", "Helvetica Neue"),
            ("search Font Book for SF Mono", "SF Mono"),
            ("show installed serif fonts", "serif"),
            ("look up Futura in Font Book", "Futura"),
            ("find fonts that support Korean", "Korean"),
            ("search for monospace fonts in Font Book", "monospace"),
            ("open Font Book and find Avenir", "Avenir"),
            ("look for variable fonts", "variable fonts"),
            ("find the font called Menlo", "Menlo"),
            ("search Font Book for handwriting fonts", "handwriting"),
        ],
        bundle_id="com.apple.FontBook",
    ),
    app(
        "Freeform",
        "macos_default",
        "canvas_creation",
        CREATE_TEXT_TOOLS,
        [
            ("create a Freeform board for launch ideas", "launch ideas"),
            ("start a Freeform canvas for kitchen remodel notes", "kitchen remodel notes"),
            ("make a Freeform brainstorming board about onboarding", "onboarding"),
            ("open Freeform and create a trip planning board", "trip planning"),
            ("start a board with three columns: now next later", "now next later"),
            ("make a Freeform board for Q3 priorities", "Q3 priorities"),
            ("create a visual plan for the podcast episode", "podcast episode"),
            ("start a Freeform board for product risks", "product risks"),
            ("make a Freeform map of wedding tasks", "wedding tasks"),
            ("create a board for app store screenshots", "app store screenshots"),
        ],
        bundle_id="com.apple.freeform",
    ),
    app(
        "Games",
        "macos_default",
        "system_game_launcher",
        OPEN_ONLY_TOOLS,
        [
            ("open Games", None),
            ("show my games", None),
            ("open the Games app", None),
            ("bring up Games so I can pick something to play", None),
            ("show the system Games launcher", None),
            ("open Games and find Chess", None),
            ("show installed games", None),
            ("launch Games from the system", None),
            ("open Games so I can browse arcade titles", None),
            ("bring the Games screen forward", None),
        ],
        task_type="app_open",
    ),
    app(
        "Home",
        "macos_default",
        "home_control",
        SEARCH_TOOLS,
        [
            ("open Home and show living room lights", "living room lights"),
            ("find the front door camera in Home", "front door camera"),
            ("show thermostat controls in Home", "thermostat"),
            ("open Home for the bedtime scene", "bedtime scene"),
            ("find the garage door accessory", "garage door"),
            ("show kitchen speaker in Home", "kitchen speaker"),
            ("look up hallway motion sensor", "hallway motion sensor"),
            ("open Home and find office lamp", "office lamp"),
            ("show the vacation scene", "vacation scene"),
            ("find the back patio lights", "back patio lights"),
        ],
        bundle_id="com.apple.Home",
    ),
    app(
        "Image Capture",
        "macos_default",
        "device_import",
        OPEN_ONLY_TOOLS,
        [
            ("open Image Capture to import from my scanner", None),
            ("launch Image Capture for the camera card", None),
            ("open Image Capture so I can scan receipts", None),
            ("bring up Image Capture for my printer scanner", None),
            ("start Image Capture to pull photos from a device", None),
            ("open Image Capture for a document scan", None),
            ("launch Image Capture and show connected cameras", None),
            ("open the Mac scanning utility", None),
            ("start Image Capture for an old camera", None),
            ("open Image Capture to import photos", None),
        ],
        bundle_id="com.apple.Image_Capture",
        task_type="app_open",
    ),
    app(
        "Image Playground",
        "macos_default_conditional",
        "image_generation",
        CREATE_TEXT_TOOLS,
        [
            ("create an Image Playground picture of a cozy reading nook", "cozy reading nook"),
            ("make an Image Playground image of a robot barista", "robot barista"),
            ("generate a sticker style corgi astronaut in Image Playground", "corgi astronaut"),
            ("open Image Playground and make a watercolor mountain cabin", "watercolor mountain cabin"),
            ("create a playful avatar with purple glasses", "purple glasses"),
            ("make a birthday invitation image with balloons", "birthday invitation"),
            ("generate a tiny house in the forest", "tiny house in the forest"),
            ("create an image of a neon ramen shop", "neon ramen shop"),
            ("make a friendly dragon reading a book", "dragon reading a book"),
            ("create a poster image for study night", "study night"),
        ],
        bundle_id="com.apple.GenerativePlaygroundApp",
    ),
    app(
        "iPhone Mirroring",
        "macos_default_conditional",
        "device_mirroring",
        OPEN_ONLY_TOOLS,
        [
            ("open iPhone Mirroring", None),
            ("show my iPhone screen on this Mac", None),
            ("launch iPhone Mirroring so I can check an app", None),
            ("bring up my iPhone from the Mac", None),
            ("start iPhone Mirroring for a quick phone check", None),
            ("open the iPhone Mirroring app", None),
            ("mirror my iPhone on the desktop", None),
            ("connect to my iPhone screen", None),
            ("show iPhone Mirroring in front", None),
            ("start the Mac iPhone mirror", None),
        ],
        bundle_id="com.apple.ScreenContinuity",
        task_type="app_open",
    ),
    app(
        "Mail",
        "macos_default",
        "mail_compose_or_search",
        CREATE_TEXT_TOOLS,
        [
            ("write an email to Maya saying I will be ten minutes late", "Maya ten minutes late"),
            ("compose a follow up email about the contract draft", "contract draft"),
            ("draft an email to support asking for a refund", "support refund"),
            ("start a mail message to the design team about tomorrow's review", "design team tomorrow review"),
            ("write an email to my landlord about the sink leak", "landlord sink leak"),
            ("compose a quick thank you note to Jordan", "thank you Jordan"),
            ("draft an email asking finance for the invoice status", "finance invoice status"),
            ("start an email to recruiting with my availability", "recruiting availability"),
            ("write a mail draft for the school pickup change", "school pickup change"),
            ("compose an email to Alex with the meeting recap", "Alex meeting recap"),
        ],
        bundle_id="com.apple.mail",
    ),
    app(
        "Maps",
        "macos_default",
        "place_search",
        SEARCH_TOOLS,
        [
            ("show directions to SFO in Maps", "SFO"),
            ("find coffee near Union Square", "coffee near Union Square"),
            ("open Maps and search for Yosemite Valley", "Yosemite Valley"),
            ("get walking directions to the nearest pharmacy", "nearest pharmacy"),
            ("find Korean BBQ near me in Maps", "Korean BBQ"),
            ("show traffic to downtown Los Angeles", "downtown Los Angeles"),
            ("search Maps for Golden Gate Park", "Golden Gate Park"),
            ("find the closest EV charger", "EV charger"),
            ("show route to 1 Infinite Loop", "1 Infinite Loop"),
            ("look up bookstores near Brooklyn", "bookstores near Brooklyn"),
        ],
        bundle_id="com.apple.Maps",
    ),
    app(
        "Messages",
        "macos_default",
        "message_compose",
        TEXT_ENTRY_TOOLS,
        [
            ("text Sam that I am on my way", "Sam I am on my way"),
            ("send mom a message asking if she needs groceries", "mom groceries"),
            ("message the study group that I will join late", "study group join late"),
            ("text Jordan the address for dinner", "Jordan address for dinner"),
            ("send Alex a quick congratulations message", "Alex congratulations"),
            ("message Maya with the flight number", "Maya flight number"),
            ("text the team standup moved to 10", "team standup moved to 10"),
            ("send dad a message about Sunday lunch", "dad Sunday lunch"),
            ("message Priya asking for the deck link", "Priya deck link"),
            ("text Casey that the package arrived", "Casey package arrived"),
        ],
        bundle_id="com.apple.MobileSMS",
    ),
    app(
        "Mission Control",
        "macos_default",
        "system_navigation",
        OPEN_ONLY_TOOLS,
        [
            ("show Mission Control", None),
            ("open Mission Control so I can pick a window", None),
            ("show all desktops with Mission Control", None),
            ("bring up the Mac window overview", None),
            ("open Mission Control for space switching", None),
            ("show all open windows", None),
            ("launch Mission Control", None),
            ("open the desktop overview", None),
            ("show me my spaces", None),
            ("switch through Mission Control", None),
        ],
        bundle_id="com.apple.exposelauncher",
        task_type="app_open",
    ),
    app(
        "Music",
        "macos_default",
        "media_playback",
        SEARCH_TOOLS,
        [
            ("play some Justin Bieber", "Justin Bieber"),
            ("play the new Taylor Swift album", "Taylor Swift"),
            ("open Music and search for Miles Davis Kind of Blue", "Miles Davis Kind of Blue"),
            ("play lo-fi beats in Music", "lo-fi beats"),
            ("find songs by Bad Bunny", "Bad Bunny"),
            ("play my focus playlist", "focus playlist"),
            ("search Music for Fleetwood Mac Dreams", "Fleetwood Mac Dreams"),
            ("put on relaxing piano music", "relaxing piano"),
            ("play the soundtrack from Interstellar", "Interstellar soundtrack"),
            ("find K-pop workout songs", "K-pop workout"),
        ],
        bundle_id="com.apple.Music",
    ),
    app(
        "News",
        "macos_default",
        "news_search",
        SEARCH_TOOLS,
        [
            ("search News for Apple earnings", "Apple earnings"),
            ("open News and find climate stories", "climate"),
            ("show news about the Warriors", "Warriors"),
            ("find technology headlines in News", "technology"),
            ("search Apple News for housing market", "housing market"),
            ("show me local San Francisco news", "San Francisco"),
            ("find articles about AI chips", "AI chips"),
            ("look up election coverage in News", "election"),
            ("search News for Formula 1", "Formula 1"),
            ("find business stories about interest rates", "interest rates"),
        ],
        bundle_id="com.apple.news",
    ),
    app(
        "Notes",
        "macos_default",
        "note_creation",
        CREATE_TEXT_TOOLS,
        [
            ("write a short poem in Notes", "poem"),
            ("create a grocery list in Notes with eggs spinach and rice", "eggs spinach rice"),
            ("start a note called launch checklist", "launch checklist"),
            ("write meeting notes for design critique", "design critique"),
            ("make a note with packing list for Seoul", "packing list Seoul"),
            ("draft a thank you note to Jordan in Notes", "thank you Jordan"),
            ("create a note about books to read this summer", "books to read"),
            ("write a quick recipe note for miso soup", "miso soup"),
            ("start a daily journal note about what went well", "what went well"),
            ("make a note with questions for the doctor", "questions doctor"),
        ],
        bundle_id="com.apple.Notes",
    ),
    app(
        "Passwords",
        "macos_default",
        "password_search",
        SEARCH_TOOLS,
        [
            ("open Passwords and find my GitHub login", "GitHub"),
            ("look up the Wi-Fi password in Passwords", "Wi-Fi"),
            ("find my bank password entry", "bank"),
            ("search Passwords for apple.com", "apple.com"),
            ("open Passwords and find the Netflix account", "Netflix"),
            ("look for the router login", "router"),
            ("find the payroll portal password entry", "payroll portal"),
            ("search saved passkeys for Google", "Google"),
            ("find my travel site login", "travel"),
            ("look up the password for my printer admin", "printer admin"),
        ],
        bundle_id="com.apple.Passwords",
    ),
    app(
        "Phone",
        "macos_default_conditional",
        "phone_call",
        SEARCH_TOOLS,
        [
            ("call mom on Phone", "mom"),
            ("open Phone and call the dentist", "dentist"),
            ("dial Alex Kim", "Alex Kim"),
            ("call the pizza place from Phone", "pizza place"),
            ("start a phone call with Jordan", "Jordan"),
            ("call my brother", "brother"),
            ("open Phone and search for pharmacy", "pharmacy"),
            ("dial the office front desk", "office front desk"),
            ("call Casey back", "Casey"),
            ("start a call with the plumber", "plumber"),
        ],
        bundle_id="com.apple.TelephonyUtilities",
    ),
    app(
        "Photo Booth",
        "macos_default",
        "camera_capture",
        OPEN_ONLY_TOOLS,
        [
            ("open Photo Booth for a quick selfie", None),
            ("launch Photo Booth and get the camera ready", None),
            ("open the Mac photo booth camera", None),
            ("start Photo Booth for a profile picture", None),
            ("bring up Photo Booth", None),
            ("open Photo Booth so I can take a picture", None),
            ("launch Photo Booth for a silly photo", None),
            ("open the built in camera app", None),
            ("show Photo Booth in front", None),
            ("start Photo Booth camera preview", None),
        ],
        bundle_id="com.apple.PhotoBooth",
        task_type="app_open",
    ),
    app(
        "Photos",
        "macos_default",
        "photo_search",
        SEARCH_TOOLS,
        [
            ("find beach photos from last summer", "beach last summer"),
            ("search Photos for pictures of Luna", "Luna"),
            ("open Photos and find screenshots from January", "screenshots January"),
            ("show photos from Seoul", "Seoul"),
            ("find pictures of receipts in Photos", "receipts"),
            ("search Photos for birthday cake", "birthday cake"),
            ("find videos from Yosemite", "Yosemite"),
            ("show photos of my passport", "passport"),
            ("search for sunsets in Photos", "sunsets"),
            ("find pictures from Thanksgiving", "Thanksgiving"),
        ],
        bundle_id="com.apple.Photos",
    ),
    app(
        "Podcasts",
        "macos_default",
        "podcast_search",
        SEARCH_TOOLS,
        [
            ("play the latest episode of Radiolab", "Radiolab"),
            ("search Podcasts for design podcasts", "design podcasts"),
            ("find The Daily in Podcasts", "The Daily"),
            ("play a meditation podcast", "meditation"),
            ("search for episodes about space exploration", "space exploration"),
            ("open Podcasts and find Acquired", "Acquired"),
            ("play the newest episode of Decoder", "Decoder"),
            ("find podcasts about startup sales", "startup sales"),
            ("search Podcasts for Korean learning", "Korean learning"),
            ("play my saved news podcast", "saved news"),
        ],
        bundle_id="com.apple.podcasts",
    ),
    app(
        "Preview",
        "macos_default",
        "document_viewer",
        OPEN_ONLY_TOOLS,
        [
            ("open Preview so I can view a PDF", None),
            ("launch Preview for image markup", None),
            ("open Preview to combine PDFs", None),
            ("bring up Preview for signing a document", None),
            ("start Preview for a screenshot annotation", None),
            ("open the Mac PDF viewer", None),
            ("launch Preview and get ready to export an image", None),
            ("open Preview for document markup", None),
            ("show Preview in front", None),
            ("open Preview to inspect a PNG", None),
        ],
        bundle_id="com.apple.Preview",
        task_type="app_open",
    ),
    app(
        "QuickTime Player",
        "macos_default",
        "media_recording",
        OPEN_ONLY_TOOLS,
        [
            ("open QuickTime Player for a screen recording", None),
            ("launch QuickTime to record audio", None),
            ("open QuickTime Player for a movie recording", None),
            ("start QuickTime so I can trim a video", None),
            ("bring up QuickTime Player", None),
            ("open QuickTime for camera recording", None),
            ("launch the Mac video player", None),
            ("open QuickTime to play a mov file", None),
            ("start QuickTime for a new screen capture", None),
            ("show QuickTime Player in front", None),
        ],
        bundle_id="com.apple.QuickTimePlayerX",
        task_type="app_open",
    ),
    app(
        "Reminders",
        "macos_default",
        "reminder_creation",
        TEXT_ENTRY_TOOLS,
        [
            ("remind me to water the basil tomorrow morning", "water the basil tomorrow morning"),
            ("create a reminder to pay rent on the first", "pay rent on the first"),
            ("add buy coffee filters to Reminders", "buy coffee filters"),
            ("remind me to call the dentist at 3 PM", "call the dentist 3 PM"),
            ("make a reminder for passport renewal next month", "passport renewal next month"),
            ("add pick up dry cleaning to Reminders", "pick up dry cleaning"),
            ("remind me to send the deck Friday", "send the deck Friday"),
            ("create a reminder to stretch after lunch", "stretch after lunch"),
            ("add cancel trial subscription tomorrow", "cancel trial subscription tomorrow"),
            ("remind me to charge the camera batteries", "charge camera batteries"),
        ],
        bundle_id="com.apple.reminders",
    ),
    app(
        "Safari",
        "macos_default",
        "web_navigation",
        ADDRESS_TOOLS,
        [
            ("go to cnn.com", "cnn.com"),
            ("open apple.com in Safari", "apple.com"),
            ("take me to github.com/openai", "github.com/openai"),
            ("browse to the New York Times homepage", "nytimes.com"),
            ("open the Stripe docs website", "stripe.com/docs"),
            ("go to weather.gov", "weather.gov"),
            ("open localhost:3000 in Safari", "localhost:3000"),
            ("visit wikipedia.org/wiki/Macintosh", "wikipedia.org/wiki/Macintosh"),
            ("open the Stanford admissions page", "stanford.edu"),
            ("go to maps.google.com", "maps.google.com"),
        ],
        bundle_id="com.apple.Safari",
    ),
    app(
        "Shortcuts",
        "macos_default",
        "shortcut_search",
        SEARCH_TOOLS,
        [
            ("run my morning routine shortcut", "morning routine"),
            ("open Shortcuts and find resize images", "resize images"),
            ("search Shortcuts for log water", "log water"),
            ("run the shortcut called meeting notes", "meeting notes"),
            ("find the clean downloads shortcut", "clean downloads"),
            ("open Shortcuts and search invoice pdf", "invoice pdf"),
            ("run focus mode shortcut", "focus mode"),
            ("find shortcut for share ETA", "share ETA"),
            ("search for the convert HEIC shortcut", "convert HEIC"),
            ("run my end of day shortcut", "end of day"),
        ],
        bundle_id="com.apple.shortcuts",
    ),
    app(
        "Siri",
        "macos_default",
        "assistant_query",
        TEXT_ENTRY_TOOLS,
        [
            ("ask Siri what song is playing", "what song is playing"),
            ("ask Siri to set a five minute timer", "five minute timer"),
            ("ask Siri the weather in Seoul", "weather in Seoul"),
            ("ask Siri to open my downloads folder", "open downloads folder"),
            ("ask Siri how tall Mount Fuji is", "Mount Fuji"),
            ("ask Siri to turn on Do Not Disturb", "Do Not Disturb"),
            ("ask Siri for my next meeting", "next meeting"),
            ("ask Siri to play jazz", "play jazz"),
            ("ask Siri what time it is in London", "time in London"),
            ("ask Siri to remind me to drink water", "remind me drink water"),
        ],
        bundle_id="com.apple.Siri",
    ),
    app(
        "Stickies",
        "macos_default",
        "sticky_note_creation",
        CREATE_TEXT_TOOLS,
        [
            ("make a sticky note that says call plumber", "call plumber"),
            ("create a sticky with today's top three priorities", "top three priorities"),
            ("write a Stickies note for parking level B2", "parking level B2"),
            ("make a sticky note with the Wi-Fi password reminder", "Wi-Fi password"),
            ("start a Stickies note for grocery basics", "grocery basics"),
            ("write a sticky that says standup moved to 10", "standup moved to 10"),
            ("create a quick sticky note for invoice due Friday", "invoice due Friday"),
            ("make a sticky with the hotel confirmation number", "hotel confirmation"),
            ("write a Stickies note about watering plants", "watering plants"),
            ("create a sticky note called do before leaving", "do before leaving"),
        ],
        bundle_id="com.apple.Stickies",
    ),
    app(
        "Stocks",
        "macos_default",
        "market_search",
        SEARCH_TOOLS,
        [
            ("show Apple stock in Stocks", "Apple"),
            ("look up NVDA in Stocks", "NVDA"),
            ("open Stocks and search for Microsoft", "Microsoft"),
            ("show the S&P 500 in Stocks", "S&P 500"),
            ("find Tesla stock", "Tesla"),
            ("search Stocks for Bitcoin", "Bitcoin"),
            ("show the Nasdaq index", "Nasdaq"),
            ("look up TSMC in Stocks", "TSMC"),
            ("find the dollar yen exchange rate", "dollar yen"),
            ("show Berkshire Hathaway in Stocks", "Berkshire Hathaway"),
        ],
        bundle_id="com.apple.stocks",
    ),
    app(
        "System Settings",
        "macos_default",
        "settings_search",
        SEARCH_TOOLS,
        [
            ("open Bluetooth settings", "Bluetooth"),
            ("show display settings", "display"),
            ("search System Settings for keyboard shortcuts", "keyboard shortcuts"),
            ("open privacy settings for microphone", "microphone"),
            ("show battery settings", "battery"),
            ("find login items in System Settings", "login items"),
            ("open trackpad settings", "trackpad"),
            ("search settings for firewall", "firewall"),
            ("show storage settings", "storage"),
            ("open accessibility voice control settings", "voice control"),
        ],
        bundle_id="com.apple.systempreferences",
    ),
    app(
        "TextEdit",
        "macos_default",
        "document_creation",
        CREATE_TEXT_TOOLS,
        [
            ("write a plain text resignation draft in TextEdit", "resignation draft"),
            ("create a TextEdit document with meeting agenda bullets", "meeting agenda"),
            ("open TextEdit and write a packing checklist", "packing checklist"),
            ("draft a short cover letter in TextEdit", "cover letter"),
            ("make a text file with project risks", "project risks"),
            ("write a quick README outline in TextEdit", "README outline"),
            ("start a TextEdit doc for interview questions", "interview questions"),
            ("create a note in TextEdit about dinner ideas", "dinner ideas"),
            ("write a bug report template in TextEdit", "bug report template"),
            ("draft a friendly birthday message in TextEdit", "birthday message"),
        ],
        bundle_id="com.apple.TextEdit",
    ),
    app(
        "Time Machine",
        "macos_default",
        "backup_utility",
        OPEN_ONLY_TOOLS,
        [
            ("open Time Machine", None),
            ("show my Time Machine backups", None),
            ("launch Time Machine settings", None),
            ("open the Mac backup app", None),
            ("start Time Machine so I can restore a file", None),
            ("bring up Time Machine", None),
            ("open Time Machine backup browser", None),
            ("show backup history with Time Machine", None),
            ("launch the backup restore interface", None),
            ("open Time Machine in front", None),
        ],
        bundle_id="com.apple.backup.launcher",
        task_type="app_open",
    ),
    app(
        "Tips",
        "macos_default",
        "help_search",
        SEARCH_TOOLS,
        [
            ("search Tips for Stage Manager", "Stage Manager"),
            ("open Tips and find trackpad gestures", "trackpad gestures"),
            ("show tips about keyboard shortcuts", "keyboard shortcuts"),
            ("find Tips for using widgets", "widgets"),
            ("search Tips for Focus modes", "Focus modes"),
            ("open Tips about iPhone Mirroring", "iPhone Mirroring"),
            ("find tips for screenshots", "screenshots"),
            ("search Tips for Safari profiles", "Safari profiles"),
            ("show Mac tips for window tiling", "window tiling"),
            ("find Tips about passwords", "passwords"),
        ],
        bundle_id="com.apple.tips",
    ),
    app(
        "TV",
        "macos_default",
        "video_search",
        SEARCH_TOOLS,
        [
            ("search TV for Severance", "Severance"),
            ("open TV and find Ted Lasso", "Ted Lasso"),
            ("play my next episode in TV", "next episode"),
            ("search Apple TV for science documentaries", "science documentaries"),
            ("find movies with Denzel Washington", "Denzel Washington"),
            ("open TV and search for Foundation", "Foundation"),
            ("find family movies in TV", "family movies"),
            ("search TV for MLS highlights", "MLS highlights"),
            ("play the show I was watching last night", "last night"),
            ("find new releases in TV", "new releases"),
        ],
        bundle_id="com.apple.TV",
    ),
    app(
        "Utilities",
        "macos_default",
        "utility_folder_open",
        OPEN_ONLY_TOOLS,
        [
            ("open Utilities", None),
            ("show the Utilities folder", None),
            ("open the Mac Utilities folder", None),
            ("bring up Utilities so I can launch Disk Utility", None),
            ("open Utilities and show Activity Monitor", None),
            ("show me the folder with Terminal and Disk Utility", None),
            ("open Utilities to find Keychain Access", None),
            ("launch the Utilities folder from Applications", None),
            ("open Utilities so I can check Console", None),
            ("show Applications Utilities", None),
        ],
        task_type="app_open",
    ),
    app(
        "Voice Memos",
        "macos_default",
        "audio_recording",
        OPEN_ONLY_TOOLS,
        [
            ("open Voice Memos to record an idea", None),
            ("start Voice Memos for a quick recording", None),
            ("launch Voice Memos before the interview", None),
            ("open the Mac audio memo app", None),
            ("bring up Voice Memos for a song sketch", None),
            ("start Voice Memos so I can record notes", None),
            ("open Voice Memos for a lecture recording", None),
            ("launch Voice Memos and get ready to record", None),
            ("open my voice recorder", None),
            ("show Voice Memos in front", None),
        ],
        bundle_id="com.apple.VoiceMemos",
        task_type="app_open",
    ),
    app(
        "Weather",
        "macos_default",
        "weather_lookup",
        SEARCH_TOOLS,
        [
            ("show me the weather for San Francisco", "San Francisco"),
            ("check tomorrow's weather in Seoul", "Seoul"),
            ("open Weather and search for New York", "New York"),
            ("what is the forecast for Yosemite", "Yosemite"),
            ("show Weather for London this weekend", "London"),
            ("check if it will rain in Portland", "Portland"),
            ("look up weather in Tokyo", "Tokyo"),
            ("show the hourly forecast for Austin", "Austin"),
            ("open Weather for Lake Tahoe", "Lake Tahoe"),
            ("check the temperature in Paris", "Paris"),
        ],
        bundle_id="com.apple.weather",
    ),
    app(
        "GarageBand",
        "apple_first_party_optional",
        "music_creation",
        CREATE_TEXT_TOOLS,
        [
            ("start a GarageBand project for a podcast intro", "podcast intro"),
            ("open GarageBand and create a piano sketch", "piano sketch"),
            ("make a GarageBand project for a lo-fi beat", "lo-fi beat"),
            ("start recording a guitar idea in GarageBand", "guitar idea"),
            ("create a GarageBand song called rainy evening", "rainy evening"),
            ("open GarageBand for a voiceover session", "voiceover session"),
            ("start a drum loop project in GarageBand", "drum loop"),
            ("make a new GarageBand project for meditation music", "meditation music"),
            ("open GarageBand and draft a bassline idea", "bassline idea"),
            ("start a music project for the trailer", "trailer"),
        ],
        bundle_id="com.apple.garageband10",
    ),
    app(
        "iMovie",
        "apple_first_party_optional",
        "video_creation",
        CREATE_TEXT_TOOLS,
        [
            ("create an iMovie project for the vacation clips", "vacation clips"),
            ("open iMovie and start a birthday montage", "birthday montage"),
            ("make an iMovie trailer about the product launch", "product launch"),
            ("start a new iMovie project for the interview", "interview"),
            ("create an iMovie edit called demo reel", "demo reel"),
            ("open iMovie for a quick social video", "social video"),
            ("start a movie project for wedding highlights", "wedding highlights"),
            ("make an iMovie project for screen recordings", "screen recordings"),
            ("create an iMovie project about the road trip", "road trip"),
            ("open iMovie and start a recap video", "recap video"),
        ],
        bundle_id="com.apple.iMovieApp",
    ),
    app(
        "Keynote",
        "apple_first_party_optional",
        "presentation_creation",
        CREATE_TEXT_TOOLS,
        [
            ("create a Keynote deck for the Q3 roadmap", "Q3 roadmap"),
            ("start a presentation about onboarding metrics", "onboarding metrics"),
            ("make a Keynote pitch deck for the coffee shop idea", "coffee shop idea"),
            ("open Keynote and draft slides for the board meeting", "board meeting"),
            ("create a presentation with five slides about climate risk", "climate risk"),
            ("start a Keynote deck called launch narrative", "launch narrative"),
            ("make a talk outline in Keynote for AI safety", "AI safety"),
            ("create a Keynote presentation for the school fundraiser", "school fundraiser"),
            ("open Keynote and make a demo day deck", "demo day"),
            ("start slides for the customer research readout", "customer research"),
        ],
        bundle_id="com.apple.iWork.Keynote",
    ),
    app(
        "Numbers",
        "apple_first_party_optional",
        "spreadsheet_creation",
        CREATE_TEXT_TOOLS,
        [
            {
                "command": "create a table in Numbers with the market cap of the 10 largest companies in the S&P",
                "hints": ["market cap", "S&P"],
                "requiredAppChain": ["Stocks", "Numbers"],
                "requiredSourceApps": ["Stocks"],
                "chainReason": "Needs a market-data lookup before creating the spreadsheet table.",
            },
            ("make a Numbers budget table for rent groceries transit and savings", "rent groceries transit savings"),
            ("open Numbers and create a sales pipeline table", "sales pipeline"),
            ("build a workout tracker spreadsheet in Numbers", "workout tracker"),
            ("create a meal plan table for the week", "meal plan"),
            ("make a Numbers table comparing three apartment options", "apartment options"),
            ("start a spreadsheet for invoice status by client", "invoice status"),
            ("create a project risk register in Numbers", "risk register"),
            ("make a travel cost table for Seoul flights hotels and food", "Seoul flights hotels food"),
            ("open Numbers and create a reading list with ratings", "reading list ratings"),
        ],
        bundle_id="com.apple.iWork.Numbers",
    ),
    app(
        "Pages",
        "apple_first_party_optional",
        "document_creation",
        CREATE_TEXT_TOOLS,
        [
            ("draft a one page proposal in Pages for the community garden", "community garden"),
            ("create a Pages document for my resume summary", "resume summary"),
            ("open Pages and write a cover letter for a design role", "design role"),
            ("start a Pages report about customer interviews", "customer interviews"),
            ("make a Pages flyer for the neighborhood cleanup", "neighborhood cleanup"),
            ("create a Pages document with a project brief", "project brief"),
            ("draft a letter to the school principal in Pages", "school principal"),
            ("open Pages and write a short newsletter intro", "newsletter intro"),
            ("start a Pages document called grant application notes", "grant application notes"),
            ("create a polished meeting recap in Pages", "meeting recap"),
        ],
        bundle_id="com.apple.iWork.Pages",
    ),
]


def slug(value: str) -> str:
    chars: list[str] = []
    previous_dash = False
    for character in value.lower():
        if character.isalnum():
            chars.append(character)
            previous_dash = False
        elif not previous_dash:
            chars.append("-")
            previous_dash = True
    return "".join(chars).strip("-")


def as_hints(value: str | list[str] | None) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    return value


def build_cases() -> list[dict[str, Any]]:
    cases: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    for spec in APP_SPECS:
        if len(spec["cases"]) != CASES_PER_APP:
            raise ValueError(f"{spec['name']} has {len(spec['cases'])} cases, expected {CASES_PER_APP}")
        app_slug = slug(spec["name"])
        for index, case_spec in enumerate(spec["cases"], start=1):
            command, hints, overrides = parse_case_spec(case_spec)
            case_id = f"{SUITE_ID}/{app_slug}-{index:02d}"
            if case_id in seen_ids:
                raise ValueError(f"duplicate case id {case_id}")
            seen_ids.add(case_id)
            query_hints = as_hints(hints)
            expected: dict[str, Any] = {
                "taskType": spec["taskType"],
                "targetAppName": spec["name"],
                "appName": spec["name"],
                "requiredTools": spec["requiredTools"],
                "responseMode": "action",
                "confidenceAtLeast": 0.55,
            }
            if query_hints:
                expected["queryContainsAny"] = query_hints
            else:
                expected["queryOptional"] = True
            for key in [
                "requiredAppChain",
                "requiredSourceApps",
                "chainReason",
            ]:
                if key in overrides:
                    expected[key] = overrides[key]

            cases.append(
                {
                    "id": case_id,
                    "suiteID": SUITE_ID,
                    "source": SOURCE,
                    "command": command,
                    "app": {
                        "name": spec["name"],
                        "bundleIdentifier": spec["bundleIdentifier"],
                        "defaultClass": spec["defaultClass"],
                        "category": spec["category"],
                    },
                    "expected": expected,
                }
            )
    return cases


def parse_case_spec(
    case_spec: tuple[str, str | list[str] | None] | dict[str, Any]
) -> tuple[str, str | list[str] | None, dict[str, Any]]:
    if isinstance(case_spec, dict):
        command = str(case_spec["command"])
        hints = case_spec.get("hints")
        overrides = {
            key: value
            for key, value in case_spec.items()
            if key not in {"command", "hints"}
        }
        return command, hints, overrides
    command, hints = case_spec
    return command, hints, {}


def build_manifest(cases: list[dict[str, Any]]) -> dict[str, Any]:
    class_counts: dict[str, int] = {}
    category_counts: dict[str, int] = {}
    for spec in APP_SPECS:
        class_counts[spec["defaultClass"]] = class_counts.get(spec["defaultClass"], 0) + 1
        category_counts[spec["category"]] = category_counts.get(spec["category"], 0) + 1

    return {
        "suiteID": SUITE_ID,
        "source": SOURCE,
        "caseCount": len(cases),
        "appCount": len(APP_SPECS),
        "casesPerApp": CASES_PER_APP,
        "defaultClassCounts": dict(sorted(class_counts.items())),
        "categoryCounts": dict(sorted(category_counts.items())),
        "includedApps": [
            {
                "name": spec["name"],
                "bundleIdentifier": spec["bundleIdentifier"],
                "defaultClass": spec["defaultClass"],
                "category": spec["category"],
                "caseCount": CASES_PER_APP,
            }
            for spec in APP_SPECS
        ],
        "privacy": {
            "sourceInventoryPolicy": "Only apps included as eval targets are persisted. Non-target source inventory is intentionally omitted.",
        },
        "schema": {
            "id": "stable unique case id",
            "command": "natural-language user command",
            "expected.taskType": "expected task intent type",
            "expected.targetAppName": "expected app target",
            "expected.requiredTools": "tools that must be present if an action plan is returned",
            "expected.requiredAppChain": "ordered app chain for tasks that need source apps before the destination app",
            "expected.requiredSourceApps": "apps that must be used as information sources before execution in the target app",
            "expected.queryContainsAny": "acceptable query/text hints when text input is expected",
        },
    }


def encode_jsonl(cases: list[dict[str, Any]]) -> str:
    return "".join(json.dumps(case, sort_keys=True, separators=(",", ":")) + "\n" for case in cases)


def encode_manifest(manifest: dict[str, Any]) -> str:
    return json.dumps(manifest, indent=2, sort_keys=True) + "\n"


def validate_cases(cases: list[dict[str, Any]], manifest: dict[str, Any]) -> None:
    if len(cases) != len(APP_SPECS) * CASES_PER_APP:
        raise ValueError("case count does not match app count * cases per app")
    ids = [case["id"] for case in cases]
    if len(ids) != len(set(ids)):
        raise ValueError("duplicate case ids")
    app_case_counts: dict[str, int] = {}
    for case in cases:
        app_name = case["app"]["name"]
        app_case_counts[app_name] = app_case_counts.get(app_name, 0) + 1
        expected = case["expected"]
        if expected["responseMode"] != "action":
            raise ValueError(f"{case['id']} has unexpected response mode")
        if not expected["requiredTools"] and not expected.get("queryOptional"):
            raise ValueError(f"{case['id']} has neither tools nor optional query marker")
        if "requiredAppChain" in expected:
            chain = expected["requiredAppChain"]
            if not isinstance(chain, list) or len(chain) < 2:
                raise ValueError(f"{case['id']} has invalid requiredAppChain")
            if chain[-1] != expected["targetAppName"]:
                raise ValueError(f"{case['id']} app chain must end at targetAppName")
    for app_name, count in app_case_counts.items():
        if count != CASES_PER_APP:
            raise ValueError(f"{app_name} has {count} generated cases")
    if manifest["caseCount"] != len(cases):
        raise ValueError("manifest case count mismatch")


def write_outputs(cases: list[dict[str, Any]], manifest: dict[str, Any]) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    JSONL_PATH.write_text(encode_jsonl(cases), encoding="utf-8")
    MANIFEST_PATH.write_text(encode_manifest(manifest), encoding="utf-8")


def check_outputs(cases: list[dict[str, Any]], manifest: dict[str, Any]) -> int:
    expected_files = {
        JSONL_PATH: encode_jsonl(cases),
        MANIFEST_PATH: encode_manifest(manifest),
    }
    mismatches = [str(path) for path, expected in expected_files.items() if not path.exists() or path.read_text(encoding="utf-8") != expected]
    if mismatches:
        print("Out-of-date generated eval files:", file=sys.stderr)
        for mismatch in mismatches:
            print(f"  {mismatch}", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="verify generated outputs are up to date")
    args = parser.parse_args()

    cases = build_cases()
    manifest = build_manifest(cases)
    validate_cases(cases, manifest)

    if args.check:
        return check_outputs(cases, manifest)

    write_outputs(cases, manifest)
    print(f"wrote {len(cases)} cases across {len(APP_SPECS)} apps")
    print(f"jsonl: {JSONL_PATH}")
    print(f"manifest: {MANIFEST_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
