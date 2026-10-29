# Updated paper and measurements

- `final_ieee_updated.docx` is the original paper with the new measurements and corrected text. `final_ieee_updated.pdf` is a Word export of it.
- `data/` holds the raw results (`recog_run1.json`, `recog_run2.json`, `mt.json`, `e2e.json`, `switch.json`, `echo.json`, `clips.json`) and `numbers.json`, which every number in Section X is computed from.
- `figures/` holds the three new figures.

To repeat the measurements, run `backend/orchestrator/scripts/eval_pipeline.py` inside the orchestrator container (it needs the Azure keys), then `backend/orchestrator/scripts/analyze_eval.py` on the results. Set `CROSSTALK_GUARD=false` first, because that guard is for same-room phone tests and would distort the media-socket runs.

All speech is synthetic (Azure neural voices), one voice per language, 10 sentences in 4 languages, on one PC.
