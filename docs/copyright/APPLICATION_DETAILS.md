# Copyright application: details to enter

Fill in the items marked **[you]**. Everything else is ready to paste. Check each field against the form
on copyright.gov.in, because field names can change.

## 1. Work
| Field | Entry |
|---|---|
| Title of the work | TranslateLanguage |
| Category | Literary work, computer software (choose the software or computer programme option the form offers) |
| Language of the work | English (names and comments); programming languages: Dart, TypeScript, Python, Kotlin, Swift, SQL |
| Version | 1.0.0 |
| Year of creation | 2026 (first recorded commit 29 September 2026) |
| Published or unpublished | **[you]** Choose *unpublished* only if the code has not been released to the public. If the GitHub repository is public or the app has been given out widely, ask a lawyer which applies. |
| Country of first publication | **[you]** India, if published |

## 2. Applicant and owner
| Field | Entry |
|---|---|
| Name | Sharad Dixit |
| Address, nationality, phone, email | **[you]** |
| Relationship to the work | Owner |
| Authors | **[you]** See section 4. List every person who wrote part of the code. |

## 3. Description of the work (paste into the form)
TranslateLanguage is a mobile application and server software for live voice calls between two people who
speak different languages. Each person chooses the language they want to hear and read. A server receives each
person's microphone audio as 20 millisecond frames, recognizes the speech, translates it into the other
person's chosen language, synthesizes a voice in that language, and plays it to the other person, with live
captions on both screens. A person can change their language during a call. The software has three parts: a
Flutter mobile app for Android and iOS (Dart and Kotlin), a Node.js signalling service written in TypeScript
for registration, contacts, call set-up and presence, and a Python service for speech recognition,
translation, voice synthesis and echo control. It calls third-party speech and translation services and uses
open-source libraries, which are listed separately and are not part of this work.

## 4. Statement of authorship (you must make this accurate)
The form asks who wrote the work. The history of this project is:
- The repository was started on 29 September 2026 under your account.
- A large part of the code changes made on 29 and 30 October 2026, and the evaluation scripts, were written
  with Claude, an AI assistant, working from your instructions.

How the law treats code written with an AI assistant is not settled in India. Do not declare that you
personally wrote every line if that is not true. A wording you could take to a lawyer or your institution's IP
office is:

> Designed and directed by Sharad Dixit. Implemented by Sharad Dixit with the assistance of an AI coding
> assistant (Claude, by Anthropic) for parts of the code.

If anyone else wrote part of the earlier code, list them or get their written no-objection letter.

## 5. Other items the form may ask for
- Identity proof of the applicant.
- A no-objection certificate from any co-author or from your institution or employer, if they have rights.
- The source-code deposit: `source_code_first_10_pages.pdf` and `source_code_last_10_pages.pdf` in this folder.
  They are the first and last 10 pages of a 177-page listing of all 82 source files (9,697 lines).
  `source_manifest.txt` lists each file with its SHA-256 hash, so you can show which version you deposited.
- The licence statement: see `LICENSE` in the repository root (all rights reserved).
- The fee. Check the current amount on the website.

## 6. Not part of this application
- The research paper (`docs/paper-results/final_ieee_updated.docx`) is a separate work with two authors on its
  title page: you and Dr. Pritee Parwekar. Do not register it without her agreement.
- Third-party libraries and services: see `THIRD_PARTY.md`.
