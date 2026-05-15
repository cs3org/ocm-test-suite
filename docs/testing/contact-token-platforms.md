# Contact Token Platform Contracts

The `contact-token` flow is a full UI end-to-end proof. It logs in, creates an
invite, accepts the contact, proves the contact, creates and saves a file,
shares it with the established contact, and proves the receiver can see the
share.

## Distinct Actors

Sender and receiver actors must be distinct people, even when the two parties
use the same platform image. Reusing one account on both sides makes screenshots
and contact/share assertions hard to read, and it weakens the proof that OCM
created a relationship between two people.

Default Reva-based actor pairs follow the legacy stable flows:

- oCIS to oCIS: `einstein` sends to `marie`.
- OpenCloud to OpenCloud: `alan` sends to `lynn`.
- oCIS to OpenCloud: `einstein` sends to `alan`.
- OpenCloud to oCIS: `alan` sends to `marie`.

These accounts come from the platform demo-user data exposed by the oCIS and
OpenCloud images. The OCM Test Suite selects them through
`config/actors/defaults.nuon` and injects them into Cypress as `sender_username`, `sender_password`,
`receiver_username`, and `receiver_password`.

## Provider JSON

oCIS and OpenCloud need an `ocmproviders.json` that contains both the local
party and the remote party. The OCM Test Suite writes indexed
`OCM_PROVIDER_*` values into `stack.env`, and the oCIS/OpenCloud compose
cookbooks pass those values into the containers.

The DockyPody image entrypoint owns the actual JSON generation:

- If `OCM_OCM_PROVIDER_AUTHORIZER_PROVIDERS_FILE` is set, the image treats that
  as an explicit mounted file and does not generate a replacement.
- If that variable is unset and `OCM_PROVIDER_0_DOMAIN` is present, the image
  generates the default provider file from indexed `OCM_PROVIDER_<n>_*` values.
- If neither is present, the image ships its template fallback.

For OCM Test Suite runs, the intended path is generated mode.
`OCM_PROVIDER_0_*` describes the sender party and `OCM_PROVIDER_1_*` describes
the receiver party. Both containers receive the same provider set so either side
can resolve itself and the remote peer.

Do not move this generator into the OCM Test Suite. The JSON schema and startup
behavior belong to the DockyPody oCIS/OpenCloud images; the suite only supplies
the platform endpoint data through the compose environment.
