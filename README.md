# Blokkeneiland

Een 3D-blokkenspel voor de iPad: bouwen en mijnen op een eiland, met je eigen poppetje, dag en nacht, en tikkertje. Spelers op iPads in de buurt kunnen samen op hetzelfde eiland spelen via wifi of bluetooth (MultipeerConnectivity). Een internetverbinding is niet nodig.

## Spelen
- **Nieuw eiland**: start een nieuwe wereld. Deze iPad wordt de host; andere iPads in de buurt kunnen meedoen.
- **Verder bouwen**: ga verder op je opgeslagen eiland. Het spel slaat automatisch op.
- **Meedoen met een vriend**: zoekt eilanden op iPads in de buurt.
- Links: joystick om te lopen. Sleep over het scherm om rond te kijken. Richt het plusje op een blok en tik op **Breek** of **Bouw**. Onderin kies je het blok.
- In het pauzemenu start de host **tikkertje** (rondes van 2 minuten).

## App bouwen
Bij elke push naar `main` bouwt GitHub Actions de app op een Mac in de cloud, zonder ondertekening. Het resultaat:
- `Blokkeneiland.ipa` onder **Releases** (direct downloadbaar), en
- als artifact bij de workflow-run.

Laat het `.ipa`-bestand ondertekenen door je installatiedienst en installeer het via de link op elke iPad.

Het project wordt gegenereerd met [XcodeGen](https://github.com/yonaskolb/XcodeGen) uit `project.yml`. Lokaal op een Mac: `brew install xcodegen && xcodegen generate && open Blokkeneiland.xcodeproj`.
