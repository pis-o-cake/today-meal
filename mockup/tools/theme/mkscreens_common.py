HEAD='''<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<title>@TITLE@</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>@font-face{font-family:'Pretendard';src:url(/_blob/1b43482c59fb171bdbae3b012829170f) format('woff2');font-weight:45 920;font-style:normal;font-display:swap}@font-face{font-family:'Jua';src:url(/_blob/b80c3f239a19ae2ac0629973c9271ec7) format('woff2');font-weight:400;font-style:normal;font-display:swap}body{margin:0}</style>
</helmet>
'''
POT='M5 11h14v6a3 3 0 0 1-3 3H8a3 3 0 0 1-3-3z M3.5 11h17 M10 8.5h4 M9.5 6c0-1.2 1-1.3 1-2.5 M13.5 6c0-1.2 1-1.3 1-2.5'
MIC='M12 3a3 3 0 0 1 3 3v5a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3z M5.5 11a6.5 6.5 0 0 0 13 0 M12 17.5V21'
def head(title): return HEAD.replace('@TITLE@', title)
