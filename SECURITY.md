# Security

## What is in this repository

Shell scripts and Terraform that **you** run, with your own credentials,
against your own Google Cloud project. Nothing here runs on Nodrik's
infrastructure, and nothing here sends us anything — the scripts grant
Nodrik's service account read-only roles on the project you name, and
that is the whole of their effect.

That is the reason this repository is public: the code that asks for
access to your systems should be readable before you run it, not after.

## Reporting a vulnerability

Email **security@nodrik.dev**. Please include what you found, the file
or command it affects, and what an attacker could do with it. If it is
sensitive enough that you would rather not put it in an email, say so and
we will find another way.

Please do **not** open a public issue for a vulnerability. Every other
kind of report — a command that does not work, a document that is wrong,
a role that is wider than it needs to be — belongs in an issue, and is
welcome there.

We are a small company and will not pretend to a response time we cannot
keep. You will get a reply from a person, not an autoresponder.

## Scope

**In scope:** anything in this repository — the grant and revoke scripts,
the Terraform modules, and the documentation where it tells you to do
something unsafe. A document that describes a wider grant than the code
actually makes, or vice versa, is a security bug here and not a typo.

**Out of scope:** Nodrik's own hosted service. That is a separate
surface with its own controls, described at
<https://nodrik.dev/security>.

## What these grants actually are

Every role this repository asks for is read-only, and every one of them
is written down with what it is for. There are two lists, because there
are two kinds of grant:

- the four roles granted on day one — [`README.md`](README.md#what-nodrik-gets);
- the optional configuration role per service, granted only if you choose
  to — [`docs/granting-access.md`](docs/granting-access.md#optional-a-configuration-role-per-service).

If you find a grant in the code that appears in neither list, or that is
wider than the list says, that is exactly the kind of report this page is
for. **Those lists being true is the security property that matters most
here** — everything else in this repository is a convenience around them.
