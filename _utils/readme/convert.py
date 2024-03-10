# delete unwanted ``
FILE_NAME = 'README.md'
with open(FILE_NAME, "r", encoding='utf-8') as f:
    content = f.read()

    content=content.replace('``', '')

with open(FILE_NAME, "w", encoding='utf-8') as f:
    f.write(content)