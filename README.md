# Kinpost

A native iPhone address book for contact details that change. Keep one card, choose what each person can see, and optionally keep a copy in Apple Contacts up to date. Swift 6, SwiftUI, iOS 27+. No web service, third-party SDK, analytics, or unit-test target.

## Try it on one simulator

Open **Kinpost.xcodeproj**, select the **Kinpost** scheme and an iPhone running iOS 27 or later, and press **Run**. The simulator uses three fictional people by default; nothing in this mode is sent to iCloud. The sample book persists across launches. A physical iPhone starts with an empty private card, not sample data.

1. Start as Avery. Tap **Share my card → Phone only → Create invitation**. In a real exchange, send the link in Messages using **Send invitation**, or let the recipient scan the QR with Camera.
2. In the simulator, tap **Open as sample person → Mira Chen → Request access**. Mira cannot see Avery’s card yet. Sample links work only within the simulator installation that issued them.
3. Tap **Done**, then **Sample → Avery Morgan**. In **Access**, tap Mira’s request and approve it. Switch back to Mira and open **People → Avery Morgan**. Only the name and phone numbers appear.
4. Choose **Link to Contacts**. Create a new contact, or explicitly select an existing one. Switch to Avery, edit the number and save. Switch back to Mira: both the received card and the linked Apple contact reflect the change. You can also open the simulator’s Contacts app to inspect the result.
5. To try an introduction, use **Forward request link** on Avery’s received card. Copy the link, switch to Theo, and use **People → Open invitation**. Theo needs a *separate* approval. Decline the request as Avery; Theo still sees nothing. Revoking Mira’s access stops her updates without deleting her Apple contact.

**Prebuilt simulator download:** unzip `Kinpost-Simulator.zip` on an Apple Silicon Mac, boot an iOS 27 iPhone in Xcode’s Device Hub, then run `xcrun simctl install booted /path/to/Kinpost.app` and `xcrun simctl launch booted app.kinpost.Kinpost`. This bundle is for the simulator, not a physical phone.

## What each invitation shares

| Profile | Included |
| --- | --- |
| Phone only | Name and labeled phone numbers |
| Home | Phone only + mailing address |
| Personal | Home + birthday and anniversary |
| Household | Personal + partner and children’s names, phones, and birthdays |

Missing fields stay empty. If two profiles are approved for the same owner and reader, People shows the broadest approved one. Revoke a broader grant in **Access** to fall back to a narrower one. An owner controls the entire household card; a partner is not a co-editor.

## Drive the same behavior without an iPhone

On a Mac with Swift 6 or later, run `swift run kinpost`. Type `help` for the commands. No simulator, Contacts permission, Apple account or network is needed. Example session:

```text
invite phone
as mira
request
ls
as avery
access
approve mira:phone
number 415-555-0199
as mira
view avery
as theo
request
as avery
deny theo:phone
revoke mira:phone
as mira
ls
```

`request` without an argument reuses the most recently issued invitation in this process. `view` emits the **projected** card as JSON. `ls` as Mira shows zero received cards before approval and after revocation. Each CLI session starts fresh unless `KINPOST_SAMPLE_FILE` is set to a path for sample JSON. Use only fictional data in the sample transport.

The split follows the Core/Mobile/CLI principle in [Shopify’s Reflex guide](https://shopify.engineering/reflex). `KinpostCore` owns cards, field projection, the observable desk and its actions, and the exchange protocol. SwiftUI and the CLI call the same desk. The phone host supplies CloudKit, Contacts, QR rendering, and presentation; the CLI supplies `SampleExchange`. Navigation and unsaved form drafts stay in SwiftUI. There is no debugging socket or hidden account switcher on a physical device.

## Use real Apple accounts

The iCloud implementation is separate from the sample transport. It requires an Apple Developer team, a provisioned iCloud container, and two different iCloud accounts. Nothing here registers a developer identifier, provisions a container, deploys a schema or publishes a build automatically.

1. In Xcode, select your signing team and a unique bundle identifier. Enable **iCloud → CloudKit**, select or create `iCloud.<your bundle identifier>`, and enable **Push Notifications** and **Background Modes → Remote notifications**. The app derives the container identifier from its bundle identifier. Keep both devices on the same container and CloudKit environment.
2. Run development-signed builds on two signed-in iPhones with iCloud Drive enabled. A properly entitled, signed-in simulator can opt into the same path using the **`-iCloud`** launch argument. Do not use that flag with an unsigned simulator build.
3. Save a card as A, generate a Phone only invitation, and send the iCloud link to B. On B open it (or paste it into **People → Open invitation**) and request access. On A refresh **Access**, approve B and have B reopen the original link if Apple prompts them to accept. Check that B sees no address or household information. Repeat with a forwarded link and an unapproved third account.
4. On B opt in to Contacts. Change A’s number, remove a number, and move the address. Check B with the app foregrounded, backgrounded, and after a cold launch. Silent pushes are best effort: reopening or pulling to refresh fetches current data. An offline device cannot receive a change immediately. This version requires connectivity to save a live card; it does not queue offline edits.
5. Revoke access, refresh B, and check that the card disappears in Kinpost. Anything B previously exported, photographed or saved to Contacts is outside the owner’s control. Before TestFlight, verify this checklist and deploy the development CloudKit schema to production in Apple’s CloudKit Console.

## Privacy and storage boundaries

- The authoritative card is an unshared `PrivateCard` in the owner’s private CloudKit zone. Saving updates it and four separate `Edition` records atomically, using a record change tag to reject stale edits. The published payload is rebuilt from an allowlist; private fields are not merely hidden in SwiftUI. Card payloads use CloudKit encrypted record fields.
- One private `CKShare` per used edition has `publicPermission = .none` and `allowsAccessRequests = true`. The QR and message contain a link, not a vCard or family data. An owner adds approved requesters as read-only participants. Apple manages participant identities, share limits and invitation acceptance. See [Apple’s access request documentation](https://developer.apple.com/documentation/cloudkit/ckshare/requesters).
- Kinpost never imports or uploads the address book. Permissions are requested only when the recipient chooses to link a card. Refreshes update that specific record, not a contact guessed from its name. A new contact follows the shared name and birthday. For an existing contact, Kinpost preserves its name and birthday, manages the numbers and addresses it adds or matches, and leaves unrelated fields alone. Anniversary and relationship names can be mirrored; individual family members’ phone numbers and birthdays stay in Kinpost.
- Contact links are local to the receiving device and account. Stopping sync disconnects the link; it does not erase someone’s address book. The simulator exercises the real Contacts framework, but only its local sample exchange stands in for iCloud.
