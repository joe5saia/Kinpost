# Kinpost

A native iPhone address book for contact details that change. Keep one card, choose what each person can see, and optionally keep a copy in Apple Contacts up to date. Swift 6, SwiftUI, iOS 27+. No web service, third-party SDK, analytics, or unit-test target.

## Try it on one simulator

Open **Kinpost.xcodeproj**, select the **Kinpost** scheme and an iPhone running iOS 27 or later, and press **Run**. The simulator uses three fictional people by default; nothing in this mode is sent to iCloud. The sample book persists across launches. A physical iPhone starts with an empty private card, not sample data.

1. Start as Avery. Tap **Share my card → Phone only → Create invitation**. In a real exchange, send the link in Messages using **Send invitation**, or let the recipient scan the QR with Camera.
2. In the simulator, copy the URL using **Send invitation → Copy**, then tap **Open as sample person → Mira Chen → Accept or request access**. Mira cannot see Avery’s card yet. Sample links work only within the simulator installation that issued them.
3. Tap **Done**, then **Sample → Avery Morgan**. In **Access**, tap Mira’s request and approve it. Switch back to Mira, paste the same link in **People → Open invitation** and accept. Open **People → Avery Morgan**: only the name and phone numbers appear.
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

Missing fields stay empty. People shows the broadest **accepted** profile for each owner. In **Access**, declining allows another request; blocking prevents new requests for that share until unblocked. Unblocking is not approval. Withdraw an invitation before acceptance or revoke a participant afterward. Both apply to one profile, not every share with that person. Revoke Household while leaving Phone only in place to downgrade someone. An owner controls the entire household card; a partner is not a co-editor.

**Stop sharing with everyone** deletes that profile’s share, not its card. Resharing the same profile can reuse its URL; it does not restore old grants. **Leave this profile** (in People) removes only the current reader’s participation. Another accepted profile may then appear. Removing the final grant stops future sync after refresh, not copies outside Kinpost.

## Drive the same behavior without an iPhone

On a Mac with Swift 6 or later, run `swift run kinpost`. In a Linux orb after `.agents/setup`, use `bash -lc 'swift run kinpost'` (the login shell loads the installed toolchain), or run `.build/debug/kinpost` directly. Type `help` for the commands. No simulator, Contacts permission, Apple account or network is needed to run the sample. Example session:

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
request
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

1. In Xcode, select your signing team and a unique bundle identifier. Enable **iCloud → CloudKit**, select or create `iCloud.<your bundle identifier>`, and enable **Push Notifications** and both **Background Modes → Background fetch** and **Remote notifications**. The app derives the container identifier from its bundle identifier. Keep both devices on the same container and CloudKit environment.
   For the custom request UI, configure [iCloud Extended Share Access](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.icloud-extended-share-access) for the App ID and verify that both the signed app and its provisioning profile authorize `InProcessShareAccessRequests`. The source entitlements alone are not a grant. Kinpost does not request owner identity lookup or one-time-link access. Requester/blocked-user identity information from this API is displayed transiently, never persisted, exported or used to populate Contacts (Apple Developer Program License Agreement, Attachment 4 §3.7).
2. Run development-signed builds on two signed-in iPhones with iCloud Drive enabled. A properly entitled, signed-in simulator can opt into the same path using the **`-iCloud`** launch argument. Do not use that flag with an unsigned simulator build.
3. Save a card as A, generate a Phone only invitation, and send the iCloud link to B. On B open it (or paste it into **People → Open invitation**) and request access. On A refresh **Access**, approve B and have B reopen the original link if Apple prompts them to accept. Check that B sees no address or household information. Repeat with a forwarded link and an unapproved third account.
4. On B opt in to Contacts. Change A’s number, remove a number, and move the address. Check B with the app foregrounded, backgrounded, and after a cold launch. Silent pushes are best effort: reopening or pulling to refresh fetches current data. An offline device cannot receive a change immediately. This version requires connectivity to save a live card; it does not queue offline edits.
5. Revoke access, refresh B, and check that the card disappears in Kinpost. Anything B previously exported, photographed or saved to Contacts is outside the owner’s control. Before TestFlight, verify this checklist and deploy the development CloudKit schema to production in Apple’s CloudKit Console.
6. With A, B and C, verify deny → request again; block → no new request; unblock → still no access; withdraw before acceptance; revoke Household → fall back to Phone only. Stop one profile and reopen its forwarded link; after resharing, check that nobody regains access without approval. Leave as B and ensure C’s accepted grant still works. Switch iCloud accounts while an invitation or Contacts picker is open. Test device-side metadata, push delivery and revocation after reconnecting, not just sample buttons.
7. In **Access → Privacy and data**, export the owner card to Files and inspect it for household fields but no participants. Delete the owner card and refresh all devices: the owner can create a new card, recipients lose its profiles, independently received cards survive, and copies in Apple Contacts remain. See Apple’s [shared records](https://developer.apple.com/documentation/cloudkit/shared-records), [data access and export](https://developer.apple.com/documentation/cloudkit/providing-user-access-to-cloudkit-data) and [deletion](https://developer.apple.com/documentation/cloudkit/responding-to-requests-to-delete-data) guidance.

**Before App Review:** publish the [bundled privacy policy](Kinpost/Privacy.txt) at a stable public URL and supply it in App Store Connect, provide a monitored support/privacy contact and review instructions for the multi-account flow, and answer App Privacy and age-rating questions for the shipped build. Review applicable user-generated-content safeguards with the publisher, including reporting and support; per-profile blocking is not a global abuse-reporting system. See the [App Review Guidelines §§1.2, 2.1 and 5.1](https://developer.apple.com/app-store/review/guidelines/) and [sharing HIG](https://developer.apple.com/design/human-interface-guidelines/collaboration-and-sharing). An unsigned build or a passing sample scenario is not App Review approval.

## Privacy and storage boundaries

- The authoritative card is an unshared `PrivateCard` in the owner’s private CloudKit zone. Saving updates it and four separate `Edition` records atomically, using a record change tag to reject stale edits. The published payload is rebuilt from an allowlist; private fields are not merely hidden in SwiftUI. Card payloads use CloudKit encrypted record fields.
- One private `CKShare` per used edition has `publicPermission = .none` and `allowsAccessRequests = true`. The QR and message contain a link, not a vCard or family data. The owner checks the requester’s email or phone before granting read-only access. This protects the card fields; Apple may show account information in previews or participant lists. Use a third account to inspect a forwarded link before approval and check participant visibility after approval. See [Apple’s access request documentation](https://developer.apple.com/documentation/cloudkit/ckshare/requesters).
- Kinpost never imports or uploads the address book. Permissions are requested only when the recipient chooses to link a card. Refreshes update that specific record, not a contact guessed from its name. A new contact follows the shared name and birthday. For an existing contact, Kinpost preserves its name and birthday, manages the numbers and addresses it adds or matches, and leaves unrelated fields alone. Anniversary and relationship names can be mirrored; individual family members’ phone numbers and birthdays stay in Kinpost.
- Contact links are local to the receiving device and account. Stopping sync disconnects the link; it does not erase someone’s address book. The simulator exercises the real Contacts framework, but only its local sample exchange stands in for iCloud.
