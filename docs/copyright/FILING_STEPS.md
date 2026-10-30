# How to file (India, online)

These steps are from general knowledge of the Copyright Office process. The website may have changed, so
follow what it shows if it differs. This is not legal advice.

1. Go to the Copyright Office website, https://copyright.gov.in, and create an account (e-filing).
2. Choose to register a copyright and start the online form for a literary work (computer software).
3. Enter the details from `APPLICATION_DETAILS.md`. Check that the author and owner entries are true.
4. Upload the documents:
   - `source_code_first_10_pages.pdf` and `source_code_last_10_pages.pdf`
   - your identity proof
   - any no-objection letters, if someone else has rights
5. Pay the fee online, in your own name. I cannot do this for you.
6. Submit, and note the **Diary number** you are given.
7. There is a waiting period (about 30 days) in which anyone may object. If nobody does, the application is
   examined. You may be asked for corrections or for a hard copy of the work.
8. When it is accepted you receive a registration certificate. Keep the diary number and the hashes in
   `source_manifest.txt` with it.

## Before you submit
- [ ] Section 4 of `APPLICATION_DETAILS.md` says what is true.
- [ ] You know whether the work counts as published or unpublished.
- [ ] You have checked ownership with BITS Pilani or any employer, if their policies could apply.
- [ ] No passwords, keys or tokens appear in the deposit. A scan of the source files found none, and `.env`
      is not part of the listing. Check the PDFs once yourself.
- [ ] If you change the code after this, make a new deposit: run `python docs/copyright/make_deposit.py` from the repository root.

## After it is registered
Put a notice on the app and the repository: "(c) 2026 Sharad Dixit. All rights reserved." The `LICENSE`
file already says this. You can change the licence later, for example to MIT, if you decide to open the code.

## Regenerating the deposit
`make_deposit.py` in this folder lists every tracked source file in order, wraps lines at 100 characters
and writes 55 lines per page. It needs `pip install pymupdf` and the Consolas font (Windows).
