# Zostaje - Historia zmian

## v0.27.26101006
- bug fixes

## v0.27.26101005
- Budzet: przelacznik Statystyki / Kalendarz w tym samym stylu co Rok / Miesiac w Planowaniu


## v0.27.26101004
- Ekran pozycji: budzet pozycji na poczatku linii pod tytulem
- Kategorie zawsze alfabetycznie (po polsku), bez przeciagania
- Planowanie: Dzisiaj i przelacznik Rok / Miesiac; widok roczny pokazuje sumy roku
- Filtry kategorii w grupie Wydatki - dotycza tylko wydatkow
- Pozyczka ratalna: zakup przyciskiem Dodaj, istniejacy - Pokaz; z zakupu Otworz / Wroc do pozyczki
- Zapis pozyczki nie nadpisuje zakupu, tylko przesuwa go za data wyplaty



## v0.27.26101003
- Planowanie: Caly rok obok Dzisiaj w lewym gornym rogu
- Pasek miesiecy: same miesiace (dotkniecie wybranego wraca do calego roku)




## v0.27.26101002
- Kategorie i metody platnosci osobne dla kazdego budzetu
- Istniejace dane podzielone: uzywane w kilku budzetach - kopia w kazdym, nieuzywane - do Osobistego
- Ekrany Kategorie i Metody platnosci: lista wybranego budzetu, Kopiuj i Przenies do budzetu, Kopiuj wszystkie
- Nowy budzet z pustymi listami (podpowiedz: skopiuj z innego budzetu)
- Przenoszenie i kopiowanie do budzetu: pytanie o brakujace kategorie i metody (Dodaj je / Bez nich)
- Kopia zapasowa w wersji 9 (wszystkie kategorie i metody z budzetami)





## v0.27.26101001
- Ekran pozycji: kwota edytuje miesiac, kolko po prawej zaznacza (bez przytrzymania)
- Kafel miesiaca: dzien w linii miesiaca, brak kwoty zamiast kreski
- Duplikuj: pozycja, pozyczka, subskrypcja i zaznaczone pozycje (w tym samym budzecie, z dopiskiem kopia)






## v0.27.26101000
- Planowanie: start na biezacym miesiacu, Dzisiaj w lewym gornym rogu
- Pasek miesiecy sam przewija sie do wybranego miesiaca
- Wydatki i Pozyczki: pigulki Razem i czesci (Razem pokazuje obie listy, czesc tylko swoja)
- Zaznacz wszystkie: tylko pozycje na widoku







## v0.27.26100903
- Budzety z nazwami i ikonami: dowolnie wiele, przelacznik z lista u gory
- Ukrywanie budzetu zamiast trybu budzetu
- Przenies i kopiuj do innego budzetu: caly budzet, zaznaczone pozycje, pozycja, pozyczka, subskrypcja
- Usuwanie budzetu z ostrzezeniem i opcja przeniesienia
- Budzet: zakladki Statystyki i Kalendarz w jednej linii z budzetem
- Wydatki i Pozyczki: chevron grupy zwija calosc, pilsy tylko swoje listy
- Pozyczki: osobno Karta kredytowa i Kredyty ratalne
- Subskrypcja: zmiana budzetu tylko w menu (Przenies / Kopiuj)








## v0.27.26100902
- Sekcja Pozyczki: pozyczka z karty i pozyczki ratalne
- Pozyczka ratalna: wyplata jako wplyw, raty, RRSO; z trzech wartosci liczy czwarta i sprawdza zgodnosc
- Opcjonalny zakup tego dnia jako wydatek (raty nie licza sie drugi raz)
- Pozyczki netto zamiast karty netto
- Formularz pozycji: bez gotowego ustawienia Raty









## v0.27.26100901
- Wydatki: przelacznik czesci stoi nad jej lista, przy prawej krawedzi (bez powtorzonego podtytulu)










## v0.27.26100900
- Ekran pozycji: siatka roku zamiast dlugiej listy
- Szybkie wypelnianie: kwota w puste albo zaznaczone miesiace
- Okres pozycji: miesiace przed startem i po splacie raty wyszarzone
- Wydatki: chevron w naglowku rozwija obie listy
- Excel: kolumny Od i Do











## v0.27.26100800
- Planowanie: plan roczny, kazdy miesiac z wlasna kwota
- Budzet: statystyki roku i kalendarz platnosci
- Pozyczka z karty kredytowej w planie
- Excel: plan jako tabela roku
- Kopia zapasowa w wersji 8 (z planem)
- Usuniete: Biezace, skan paragonow, Planner, synchronizacja












## v0.26.26100600
- Cykliczne i Wplywy: przy wybranym miesiacu suma grupy uwzglednia korekty kwot, tak jak pozycje pod nia













## v0.26.26082300
- Potwierdzenie platnosci z portfela telefonu (Samsung Wallet) czytane w okolo sekunde, bez silnika AI
- Nazwa sklepu, kwota i data prosto z dokumentu, bez zgadywania roku
- Odczyt nie wymaga obracania zdjecia, wiec jest szybszy














## v0.26.26081800
- Scalanie zaznaczonych wydatkow w jeden wpis: suma kwot, data najstarszej pozycji, wzorzec wybierany z listy
- Pozycje karty kredytowej sa chronione przed scaleniem, bo ich usuniecie kasuje kaskada zakup
- Splaty karty na Biezacych oraz wplywy z karty na Wplywach zwijaja sie w jeden wiersz z suma
- Rozwinieta grupa ma wciecie, wiec widac przynaleznosc pozycji















## v0.26.26081400
- Zapis w stalym miejscu na dole ekranu zamiast przycisku na koncu przewijanej listy
- Pigulka Anuluj / Zapisz jedzie nad klawiatura, wiec jest widoczna caly czas
- Dotyczy dodawania i edycji wydatku biezacego, pozycji budzetu i subskrypcji oraz arkuszy metody platnosci i kategorii
- Pigulka ma to samo rozmyte szklo co pasek nawigacji i nie zaslania siatki ikon przy edycji kategorii
- Zapis znika z paska tytulu, gdzie przy edycji dublowal przycisk z dolu
















## v0.25.26081001
- Naprawione skanowanie paragonow: w poprzednim wydaniu przestalo dzialac i pokazywalo blednie, ze wymaga Androida
- Stawka VAT nie jest juz brana za kwote (paragon na 39,00 zapisywal sie jako 23,00)
- Nazwa wydatku nie moze byc numerem ani etykieta dokumentu

















## v0.25.26081000
- Metoda platnosci moze byc karta kredytowa z liczba dni bezodsetkowych
- Wplyw jednorazowy da sie oznaczyc jako pozyczony z karty
- Zakup karta tworzy lustrzany wplyw, wiec miesiac zakupu wychodzi na zero, a koszt lauduje w miesiacu splaty
- Po zapisie pojawia sie komunikat, co automat dolozyl i na kiedy
- Toggle automatyczna przy karcie opisuje SPLATE karty
- Ikona metody platnosci jest teraz taka sama na wszystkich listach


















## v0.24.26080901
- Sortowanie sekcji miesiaca ma trzeci tryb: od najwiekszej kwoty (przycisk cykluje data / A-Z / kwota)
- Platnosci i Podsumowanie miesiaca maja osobne ustawienia widoku — sortowanie, grupowanie i zwijanie dzialaja niezaleznie
- Ustawienia widoku sa zapamietywane i przezywaja wyjscie z zakladki



















## v0.23.26080900
- Import budzetu i subskrypcji z Excela przeniesiony z menu Dodaj do Ustawien -> Eksport/import danych
- Menu Dodaj na Wplywach i Cyklicznych ma teraz tylko dodawanie
- Import DOKLADA pozycje z arkusza; nie zastepuje kopii zapasowej




















## v0.23.26080801
- Ikona pozycji bez kategorii pokazuje, do ktorej zakladki nalezy; subskrypcje maja wlasna ikone
- Przy filtrze na jeden miesiac karta pozycji pokazuje po prawej kwote korekty z tego miesiaca, a poza tym licznik korekt
- W Bilansie miesiaca mozna zwinac liste biezacych do jednego wiersza z suma (Platnosci i Podsumowanie miesiaca)
- W Platnosciach zwiniety wiersz odhacza wszystkie biezace naraz
- Menu Dodaj na Cyklicznych: Dodaj wydatek cykliczny zamiast Dodaj recznie





















## v0.22.26080800
- Zakladka Rachunki nazywa sie teraz Biezace, a Wydatki - Cykliczne. Nazwy mowia, czym te sekcje sie roznia: biezace to wydatek z konkretna data, cykliczne to koszt usredniany na miesiac
- Koperta Plannera: Na biezace wydatki
- Ikona pozycji bez kategorii pokazuje, do ktorej zakladki nalezy; subskrypcje maja wlasna ikone
- Menu Dodaj na Cyklicznych: Dodaj wydatek cykliczny zamiast Dodaj recznie
- Eksport Excela pisze Wydatek biezacy; stare arkusze importuja sie bez zmian
- Zmiana nie rusza zapisanych danych: synchronizacja z telefonem na starszej wersji dziala dalej






















## v0.21.26080400
- Pokaz kod QR na sparowanym telefonie: kolejne urzadzenie dolacza do tego samego gospodarstwa
- wymiana telefonu nie wymaga juz rozlaczania drugiej osoby























## v0.20.26080203
- zaznaczanie wielu pozycji na listach: dlugie przytrzymanie, potem kategoria, metoda platnosci, data albo usuniecie naraz
- Rachunki: zmiana daty przenosi rachunek do bilansu innego miesiaca razem z odhaczeniem platnosci
- Wydatki i Wplywy: zbiorcze wstrzymywanie i wznawianie pozycji
- dluga lista rachunkow buduje sie leniwie
























## v0.20.26080202
- Rachunki z filtrami zamiast przewijania miesiecy: kategoria, czas, sortowanie i suma widocznych pozycji
- skrot Dzisiaj w filtrze czasu (od razu biezacy miesiac)
- pasek plan/realny pokazuje sile przekroczenia: zielone = plan, czerwone = nadwyzka
- kalendarz bilansu: tap w nazwe miesiaca otwiera wybor
- okna wyboru daty i przyciski systemowe po polsku, tydzien od poniedzialku

























## v0.19.26080201
- grupy Miesiac i Statystyki zwijaja sie tapnieciem w nazwe
- sekcja Szczegoly nazywa sie teraz Limity i okresy probne


























## v0.19.26080200
- Plan podzielony na grupy: Miesiac (Plan vs Realne, Kategorie) i Statystyki (trend, podsumowanie roczne)
- wybor miesiaca i punkt startu ewidencji przeniesione do naglowkow grup
- trend zaczyna sie od punktu startu i ma tryb Oba: realne i plan na jednym wykresie
- smuklejsze karty Saldo i Koszty roczne
- rachunki maja wlasna ikone na listach miesiaca



























## v0.18.26080103
- Wykresy w Planie maja przelacznik Plan / Realne
- Nowe Podsumowanie roczne: ile z rocznego planu juz wydano, miesiac po miesiacu
- Poczatek ewidencji — uczciwe porownanie, gdy budzet zaczal sie w polowie roku
- Planner: Uzupelnij do pelnej kwoty (10 / 100 / 1000)
- Predykcja vs rzeczywistosc nazywa sie teraz Plan vs Realne
- Bilans miesiaca bez powtorzonej karty Rachunki miesiaca




























## v0.17.26080102
- Subskrypcje sa teraz sekcja Wydatkow — koniec osobnej zakladki (5 zakladek zamiast 6)
- Sekcje listy zwijane tapnieciem w naglowek; suma sekcji zostaje widoczna
- Pokaz ukryte przy filtrze lat odslania wstrzymane pozycje i anulowane subskrypcje
- Planner ma wlasny ekran — wejscie z Rachunkow i z Wydatkow
- 14 nowych ikon kategorii (ubrania, transport, dom, sport, podroze)
- Czytelne ikony paska stanu w jasnym motywie





























## v0.16.26080101
- Smuklejsze listy: pozycje bez ramek, rozdzielone separatorem, w dwoch liniach
- Ikona kategorii przy pozycji, kwota przy nazwie, opis na pelnej szerokosci
- Jeden format daty w calej liscie (RRRR-MM-DD)
- Sortowanie i grupowanie w paskach filtrow zamiast osobnej linii ikon
- Formularz pokazuje tylko typy z tej sekcji; filtr kategorii tylko tam, gdzie sa kategorie






























## v0.15.26080100
- Wiecej miejsca na tresc: znikly paski z nazwami ekranow (nazwa jest w pasku nawigacji)
- Przelacznik Osobisty/Domowy na samej gorze, wspolny dla calej aplikacji
- Sortowanie i grupowanie przy sekcjach, ktorych dotycza
- Opis sekcji (ikona i) obok przelacznika zakresu































## v0.14.26073102
- Synchronizacja gestem: przeciagnij liste w dol (zamiast przycisku w pasku)
- Eksport XLSX i PDF w jednym miejscu: Ustawienia -> Dane -> Eksport danych
- Kategorie i metody platnosci przeniesione do sekcji Personalizacja
































## v0.13.26073101
- Dociete zdjecie zapisanego rachunku trafia takze do archiwum (stara wersja jest usuwana)

































## v0.13.26073100
- Kopia zapasowa na koncie Google: automat raz na dobe, kod odzyskiwania zamiast klucza urzadzenia
- Przenoszenie rachunku miedzy budzetem osobistym a domowym (przycisk w edycji rachunku)
- Budzet domowy: kategorie i metody platnosci trafiaja na drugi telefon razem z pozycjami
- Poprawka: udostepniony rachunek nie dodaje sie ponownie przy kazdym uruchomieniu aplikacji
- Poprawka: pozycje w trakcie rozpoznawania mozna odrzucic


































## v0.12.26072700
- Budzet/Plan: jeden wykres trendu z trzema liniami (cykliczne, subskrypcje, rachunki) i chipami do wlaczania
- Plan: wspolny podzial na kategorie oraz nowa sekcja Koszty roczne
- Saldo po rozwinieciu pokazuje skad sie bierze: pasek proporcji i rozpis skladnikow
- Bilans miesiaca: nowa sekcja Rzeczywisty bilans miesiaca nad kalendarzem
- Rachunki: Planner, osobna karta miesiaca z wyborem miesiaca i przyciskiem Dzisiaj, potem lista
- Skan rachunkow dziala bez Lokalnego Silnika AI: paragony, potwierdzenia platnosci i faktury
- Skan w tle: kolejne zdjecia nie gina po wyjsciu z aplikacji



































## v0.11.26072603
- Backup obejmuje teraz takze ustawienia: walute, limit budzetu, tryb budzetu, powiadomienia, Asystenta AI, archiwum i motyw
- Sciezki zdjec rachunkow swiadomie poza plikiem - zdjec tam nie ma, wiec byly by martwe linki




































## v0.11.26072602
- Poprawka: odtwarzanie ze starszego backupu nie kasuje danych, ktorych ten plik nie zawiera (dotyczylo Plannera)
- Czyszczone sa tylko obszary faktycznie obecne w pliku





































## v0.11.26072601
- Import backupu pyta, czy odtworzyc stan z pliku (domyslnie) czy scalic z obecnymi danymi
- Poprawka: wczesniej import zawsze scalal, wiec pozycje usuniete w zrodle zostawaly i zawyzaly sumy
- Planner (kwota na rachunki) wchodzi teraz do backupu
- Przy eksporcie z haslem trzeba je powtorzyc - literowka oznaczala plik nie do odczytania
- Podsumowanie po imporcie mowi, ile pozycji usunieto






































## v0.11.26072600
- Skan rachunku ze zdjecia: aparat, galeria albo 'Udostepnij -> Zostaje'; rozpoznawanie w calosci na telefonie, bez chmury
- Paragony i zrzuty platnosci telefonem czyta szybki OCR w ok. 2 s; faktury o dowolnym ukladzie przejmuje lokalny silnik AI
- Rozpoznawanie dziala w tle - mozesz wyjsc z aplikacji, wynik czeka w sekcji 'Do zatwierdzenia'
- Zdjecie rachunku mozna przyciac do samego paragonu; opcjonalne archiwum zdjec w Documents
- Nowy uklad sekcji: Budzet (przeglad), Wplywy, Rachunki, Subskrypcje, Wydatki cykliczne
- Rachunek i wydatek jednorazowy to teraz jedno: datowany wydatek w sekcji Rachunki (oplacony albo zaplanowany)
- Planner: kwota zaplanowana w budzecie na rachunki, edytowana przy rachunkach
- Nowy cykl platnosci: wybrane miesiace roku, z presetami co 2 / 3 / 4 miesiace i co pol roku
- Tryb budzetu: Osobisty / Domowy / oba
- Podsumowanie miesiaca jako osobna sekcja, z sortowaniem i grupowaniem po typie
- Ikona 'i' przy kazdej sekcji tlumaczy, po co ona jest
- Paczka aktualizacji schudla do 43 MB







































## v0.10.26062500
- Dashboard: sekcja Saldo zostaje miesiecznie scalona w jedna karte z opisem jak liczone jest saldo
- Bilans miesiaca: lepszy opis + przytrzymanie kwoty pokazuje rozbicie roznicy wzgledem salda
- Budzet: filtr czasu (rok i miesiac) obok kategorii i typow








































## v0.9.26062401
- Nowy system motywow: tryb jasny/ciemny/systemowy x kolor (Purple Green, Laguna Ocean, Mono, Material You)
- Ustawienia podzielone na osobne ekrany (Wyglad, Dane, Aplikacja)
- Poprawki kontrastu: zaznaczone chipy oraz obramowanie paska nawigacji w trybie jasnym









































## v0.9.26062400
- Nowy system motywow: tryb jasny/ciemny/systemowy x kolor (Purple Green, Laguna Ocean, Mono, Material You)
- Ustawienia podzielone na osobne ekrany (Wyglad, Dane, Aplikacja)
- Poprawki kontrastu zaznaczonych chipow










































## v0.9.26062100
- Baner dostepnej aktualizacji na Dashboardzie











































## v0.9.26062004
- Migracja na nowy identyfikator aplikacji (reinstalacja + import backupu)












































## v0.9.26062003
- Nowa nazwa (Zostaje) i ikona aplikacji













































## v0.9.26062002
bugs














































## v0.9.26062001
- Synchronizacja budzetu domowego (preview): wspoldzielenie miedzy telefonami przez kod QR + haslo (szyfrowanie E2E)
- Modernizacja wyboru waluty















































## v0.8.26062000
dodano badge preview dla funkcji synchronizacji
















































## v0.8.26061900
-sync

















































## v0.8.26061704
- Budzet: sortowanie (A-Z / kwota), filtr typu, grupowanie wg typu
- Przelew do domowego: osobna sekcja + korekty kwoty (spojne z budzetem domowym)
- Sumy w naglowkach sekcji (miesiecznie)
- Dashboard: zwijanie kalendarza i listy platnosci


















































## v0.7.26061703
- Metody platnosci: automatyczna/manualna
- Kalendarz: wydatki auto na zolto, manualne na czerwono
- Dashboard: sekcja Platnosci (manualne do odhaczenia)
- Nowy typ wydatku: Rata (start + liczba rat lub data ostatniej)
- Pelny eksport/import Excel i backup (nic nie ginie)
- Wiecej ikon kategorii domowych



















































## v0.6.26061702
- Kategorie wydatkow w budzecie: oznaczanie pozycji i filtrowanie listy
- Kategoria w eksporcie i imporcie Excel budzetu




















































## v0.5.26061701
- Nowy wyglad Aurora: jeden ciemny motyw, gradient i powierzchnie frost
- Plywajacy szklany pasek nawigacji
- Menu Dodaj wysuwane nad przyciskiem
- Personalizacja Dashboardu: zwijanie sekcji (full/compact)
- Spojny system kolorow i zaokraglen (tokeny)





















































## v0.4.26061700
- Nowy Dashboard: pelny przeglad budzetu razem z subskrypcjami
- Budzet domowy (wspolny) obok osobistego + przelew miedzy budzetami
- Kalendarz przeplywow w widoku miesiaca (dni wplywow i wydatkow)
- Jednorazowy wplyw (premia/bonus)
- Subskrypcje: pod-zakladki Lista/Statystyki + zakres osobisty/domowy
- Excel i backup obejmuja budzet domowy
- Uproszczenie: usunieto wykrywanie nieuzywanych i koszt-za-uzycie






















































## v0.3.26061600
- Import i eksport subskrypcji do Excela (.xlsx)























































## v0.2.26040900
- bug fixes
























































## v0.2.26032905
- bug fixes

























































## v0.2.26032904
- bug fixes


























































## v0.2.26032903
- bug fixes



























































## v0.2.26032902
fix ikony




























































## v0.2.26032901
zmiana ikony aplikacji





























































## v0.1.26032900
- bug fixes






























































## v0.1.26032808
- bug fixes































































## v0.1.26032806
- bug fixes
































































## v0.1.26032805
- bug fixes

































































## v0.1.26032804
- bug fixes


































































## v0.1.26032803
OTA



































































## v0.1.26032802
- bug fixes




































































## v0.1.26032801
- bug fixes





































































## v0.1.26032800
- bug fixes
