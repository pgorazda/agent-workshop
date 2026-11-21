# Agent Workshop

> To jest tłumaczenie pliku [README.md](README.md). Jeśli wersje się różnią, obowiązuje wersja angielska. Dokumenty w `docs/` i plik `CONTRIBUTING.md` są tylko po angielsku.

Obserwuj, jak agenci programistyczni AI pracują jako pingwiny w pikselartowym warsztacie.

![Aplikacja Godot: agent myśli, używa kuźni z pomocnikiem, czeka na zgodę i kończy turę](docs/images/agent-workshop.gif)

Aktywność agenta (wywołania narzędzi, subagenci, prośby o zgodę, błędy) zamienia się w mały strumień zdarzeń. Lokalny program, **most** (bridge), przekazuje go do **aplikacji**. Tam pingwin chodzi między stanowiskami warsztatu i przy każdym rodzaju pracy używa innego narzędzia. Obsługiwani są Claude Code, OpenCode, Pi i Hermes Agent.

Ten projekt powstał głównie dla zabawy. To sposób, by oglądać pracę agentów, a nie narzędzie do monitoringu.

Agent Workshop to niezależny projekt. Nie jest tworzony, popierany ani sponsorowany przez twórców Claude Code, OpenCode, Pi ani Hermes Agent. Te nazwy należą do ich właścicieli i służą tylko do wskazania, z którymi agentami projekt współpracuje.

## Wybierz swoją drogę

| Chcę... | Idź do |
|---|---|
| Zobaczyć aplikację bez konfiguracji | [Wypróbuj aplikację](#wypróbuj-aplikację) |
| Obserwować własnego agenta | [Obserwuj prawdziwego agenta](#obserwuj-prawdziwego-agenta) |
| Zbudować ze źródeł lub zmieniać kod | [Budowanie i rozwój](#budowanie-i-rozwój) |

## Wypróbuj aplikację

1. Pobierz aplikację dla swojego systemu z [najnowszego wydania](https://github.com/pgorazda/agent-workshop/releases/latest) (`AgentWorkshop-<wersja>-<system>`) i rozpakuj ją.
2. Uruchom ją. Aplikacje nie są podpisane: na macOS kliknij ją prawym przyciskiem i wybierz Otwórz, w Windows w SmartScreen wybierz "Więcej informacji", a potem "Uruchom mimo to".
3. Naciśnij **D** i wybierz scenę. Każda scena to zmyślona sesja, która gra bez mostu i bez agenta.

## Obserwuj prawdziwego agenta

Potrzebujesz aplikacji (patrz wyżej), mostu i małego forwardera dla swojego agenta.

**1. Uruchom most.** Pobierz `AgentWorkshopBridge-<wersja>-<system>` z tego samego wydania, rozpakuj i uruchom:

```bash
./agent-workshop-bridge serve        # nasłuchuje na http://127.0.0.1:8787
```

Na macOS po rozpakowaniu uruchom raz `xattr -d com.apple.quarantine agent-workshop-bridge`. Most nie wymaga Node ani innego środowiska uruchomieniowego. Nasłuchuje tylko na `127.0.0.1` i niczego nie zapisuje.

**2. Uruchom aplikację.** Połączy się z mostem sama. Aby aplikacja uruchamiała most za Ciebie, wystartuj ją z `--start-bridge` (program mostu musi leżeć obok aplikacji albo być w `PATH`).

**3. Podłącz agenta.** Wybierz go w [docs/adapters.md](docs/adapters.md): Claude Code (hooki), OpenCode (wtyczka), Pi (rozszerzenie albo potok JSON) lub Hermes Agent (skrypt hooka). Każdy wymaga skopiowania jednego pliku albo scalenia jednej konfiguracji.

Agent może działać na innym komputerze, na przykład przez SSH: zobacz [Agent on another machine](docs/adapters.md#agent-on-another-machine) (po angielsku).

Nie masz agenta pod ręką? Odtwórz nagraną sesję, przy działającej aplikacji:

```bash
./agent-workshop-bridge replay schema/examples/claude-code-transcript.jsonl --speed 4
```

**Co opuszcza Twój komputer?** Nic. Most nasłuchuje tylko na `127.0.0.1`. Klienci nie dostają tekstu wiadomości, wyników narzędzi ani zawartości plików. Cele (polecenie lub nazwa pliku) mogą jednak trafić do strumienia: uruchom most z `--redact-targets`, aby je usunąć. Szczegóły są w [docs/adapters.md](docs/adapters.md).

## Budowanie i rozwój

Zainstaluj [mise](https://mise.jdx.dev), potem:

```bash
mise install          # Node i Rust w przypiętych wersjach
mise run bridge       # uruchom most ze źródeł
mise run replay       # wyślij do niego przykładową sesję
mise run app          # uruchom aplikację (za pierwszym razem pobiera przypiętą wersję edytora Godot)
mise run demo         # aplikacja na zmyślonej scenie, bez mostu
mise run check        # wszystkie sprawdzenia CI na Twoim komputerze
```

`mise tasks` pokazuje resztę. Zwykłe polecenia bez mise, testy, nagrywanie i wydania opisuje [CONTRIBUTING.md](CONTRIBUTING.md).

## Jak to działa

```
agent (hooki, wtyczka, rozszerzenie)  -->  most  -->  aplikacja
                  HTTP na wejściu: POST /event, POST /hook/<framework>      WebSocket na wyjściu: /ws
```

Adapter zamienia natywne zdarzenia każdego agenta na jeden, niezależny od frameworka format zdarzeń ([docs/event-schema.md](docs/event-schema.md)). Aplikacja wybiera stanowisko warsztatu z kategorii zdarzenia, nigdy z nazwy narzędzia. Gdy jeden pokój się zapełni, otwierają się kolejne pokoje (areny), a kamera przesuwa się między nimi ([docs/arenas.md](docs/arenas.md)). Dlaczego jest to zbudowane w ten sposób, opisuje [docs/design.md](docs/design.md).

![Kilka aren w aplikacji Godot: kamera przesuwa się do nowej areny, zgoda ją przywraca, a przegląd jest pod klawiszem Tab](docs/images/arena-2d-arenas.png)

## Stan

| Część | Stan |
|---|---|
| Schemat zdarzeń v1, most (Rust, jeden plik wykonywalny na system) i adaptery dla Claude Code, OpenCode, Pi i Hermes | Gotowe i przetestowane |
| Wtyczka OpenCode, rozszerzenie Pi, skrypt hooka Hermes | Napisane na podstawie opublikowanych dokumentów i typów, przetestowane na fixture'ach. **Jeszcze nie uruchomione w prawdziwym OpenCode, Pi ani Hermes** |
| Aplikacja (Godot): sesje na żywo, areny, dźwięk, siedem scen demo | Gotowa na komputery. Na prawdziwym sprzęcie uruchomiono tylko aplikację na Windows x86_64. Niezrobione: podpisywanie, tablety i telefony |

Znane ograniczenia adapterów są w [docs/adapters.md](docs/adapters.md#known-limits).

## Wygląd i dźwięk

Pokój jest narysowany w stylu własnym, w rozdzielczości 480×270 pikseli, zainspirowanym czapką pingwina (krakowską rogatywką) i polską sztuką ludową: malowanymi kwiatami z Zalipia, malarstwem ludowym z Lipnicy Murowanej, ceramiką bolesławiecką i kilimami. Aplikacja gra cztery oryginalne melodie w manierze polskich tańców ludowych (krakowiak, kujawiak, oberek i góralski) oraz pięć dźwięków zdarzeń. Cały dźwięk startuje wyłączony. Naciśnij **M**, aby go włączyć.

## Współpraca i bezpieczeństwo

[CONTRIBUTING.md](CONTRIBUTING.md) opisuje pracę nad kodem (po angielsku), [SECURITY.md](SECURITY.md) zgłaszanie problemów bezpieczeństwa prywatnie, a [kodeks postępowania](CODE_OF_CONDUCT.md) zasady współpracy.

## Układ

```
schema/      schemat zdarzeń i przykładowe sesje (zmyślone)
bridge/      most w Rust: sprawdzanie schematu, adaptery, serwer, CLI, testy
adapters/    forwardery działające w agencie lub obok niego, i ich testy
godot/       aplikacja: projekt, sceny, narzędzia i testy (godot/art/ zawiera grafikę i dźwięk)
docs/        dokumenty dla użytkowników i współtwórców
```

## Licencja

- **Kod:** MIT. Zobacz [LICENSE](LICENSE).
- **Grafika i dźwięk:** wszelkie prawa zastrzeżone. Dotyczy to kodu rysującego i dźwiękowego w `godot/art/`, obrazów i dźwięków w nim, obrazów w `docs/images/` oraz obrazów, wideo i dźwięku z nich zrobionych. Zobacz [LICENSE-ASSETS](LICENSE-ASSETS).

Czcionki Tiny5 i Silkscreen są na licencji SIL Open Font License 1.1. Wydania zawierają `THIRD-PARTY-NOTICES.txt` z licencjami silnika Godot i crate'ów Rusta, które zawierają programy.
