pandoc ./README.docx --to=gfm -o README.md --extract-media=_imgs
python ./convert.py
if %errorlevel% EQU 0 (pause) else 

