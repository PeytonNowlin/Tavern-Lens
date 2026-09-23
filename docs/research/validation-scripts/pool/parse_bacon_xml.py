import xml.etree.ElementTree as ET, json, collections
t=ET.parse('Bacon.xml').getroot()
cards={}
for e in t.findall('Entity'):
    d={'id':e.get('CardID'),'dbf':int(e.get('ID')),'tags':{}}
    for tg in e.findall('Tag'):
        n=tg.get('name') or tg.get('enumID')
        if tg.get('type')=='LocString':
            en=tg.find('enUS'); d['tags'][n]=en.text if en is not None else None
        else:
            d['tags'][n]=tg.get('value')
    for tg in e.findall('ReferencedTag'):
        pass
    cards[d['id']]=d
json.dump(cards,open('bacon.json','w'))
pool=[c for c in cards.values() if c['tags'].get('IS_BACON_POOL_MINION')=='1']
cnt=collections.Counter()
for c in pool:
    for k in c['tags']: cnt[k]+=1
for k,v in sorted(cnt.items(),key=lambda x:-x[1]):
    if 'BACON' in k or 'POOL' in k or 'SUBSET' in k or 'RACE' in k or 'DUO' in k or k.isdigit(): print(v,k)
