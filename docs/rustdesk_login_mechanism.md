# Mechanizm logowania do klienta desktop RustDesk — szczegółowa analiza

## 1. Przegląd

System logowania w kliencie desktop RustDesk umożliwia użytkownikowi uwierzytelnienie się na serwerze API (HBBS — RustDesk API Server). Logowanie jest opcjonalne, ale wymagane do korzystania z funkcji takich jak **Książka adresowa** (Address Book), **Moja grupa** (My Group) oraz **synchronizacja urządzeń**. Po zalogowaniu klient przechowuje token dostępu (`access_token`) lokalnie i automatycznie odświeża informacje o użytkowniku.

---

## 2. Punkty wejścia do logowania (UI)

Na zrzutach ekranu widoczne są trzy miejsca, z których użytkownik może zainicjować logowanie:

### 2.1. Zakładka "Książka adresowa" (Address Book) — Zdjęcie 1
Na ekranie głównym ("Pulpit"), po wybraniu ikony Książki adresowej, jeśli użytkownik **nie jest zalogowany**, wyświetlany jest przycisk **"Zaloguj"**.

Odpowiedzialny widget:
```dart
// flutter/lib/common/widgets/address_book.dart
Widget build(BuildContext context) => Obx(() {
    if (!gFFI.userModel.isLogin) {
      return Center(
          child: ElevatedButton(
              onPressed: loginDialog, child: Text(translate("Login"))));
    }
    // ...
});
```

### 2.2. Zakładka "Moja grupa" (My Group) — Zdjęcie 2
Analogicznie, w zakładce "Moja grupa", brak logowania skutkuje wyświetleniem przycisku **"Zaloguj"**.

```dart
// flutter/lib/common/widgets/my_group.dart
if (!gFFI.userModel.isLogin) {
  return Center(
      child: ElevatedButton(
          onPressed: loginDialog, child: Text(translate("Login"))));
}
```

### 2.3. Ustawienia → Konto — Zdjęcie 3
W sekcji **Ustawienia → Konto** (`_Account` widget) wyświetlany jest przycisk dynamiczny:
- **"Login"** — gdy użytkownik nie jest zalogowany
- **"Logout"** — gdy użytkownik jest zalogowany

```dart
// flutter/lib/desktop/pages/desktop_setting_page.dart
Widget accountAction() {
  return Obx(() => _Button(
      gFFI.userModel.userName.value.isEmpty ? 'Login' : 'Logout',
      () => {
            gFFI.userModel.userName.value.isEmpty
                ? loginDialog()
                : logOutConfirmDialog()
          }));
}
```

Po zalogowaniu, pod przyciskiem wyświetlana jest nazwa użytkownika:
```dart
Widget useInfo() {
  return Obx(() => Offstage(
        offstage: gFFI.userModel.userName.value.isEmpty,
        child: Column(
          children: [
            text('Username', gFFI.userModel.userName.value),
          ],
        ),
      ));
}
```

---

## 3. Dialog logowania (`loginDialog()`)

Wszystkie przyciski "Zaloguj" wywołują tę samą funkcję `loginDialog()` zdefiniowaną w:

**Plik:** `flutter/lib/common/widgets/login.dart`

### 3.1. Inicjalizacja
```dart
Future<bool?> loginDialog() async {
  var username = TextEditingController(
      text: UserModel.getLocalUserInfo()?['name'] ?? '');
  var password = TextEditingController();
  final userFocusNode = FocusNode()..requestFocus();

  String? usernameMsg;
  String? passwordMsg;
  var isInProgress = false;
  final RxString curOP = ''.obs;
  bool isCloseHovered = false;

  // Pobieranie opcji logowania OIDC (trzecich stron)
  final loginOptions = [].obs;
  Future.delayed(Duration.zero, () async {
    loginOptions.value = await UserModel.queryOidcLoginOptions();
  });
  // ...
}
```

**Kluczowe elementy:**
- Pole `username` jest wstępnie wypełniane na podstawie zapisanych danych użytkownika (`UserModel.getLocalUserInfo()`)
- Asynchronicznie pobierane są opcje logowania OIDC z serwera (`/api/login-options`)
- `curOP` śledzi aktualnie wybraną operację logowania (np. `'rustdesk'` lub nazwa providera OIDC)

### 3.2. Struktura dialogu
Dialog zawiera dwie sekcje:

1. **`LoginWidgetUserPass`** — formularz login/hasło (natywne logowanie RustDesk)
2. **`thirdAuthWidget()`** — przyciski logowania przez OIDC (Google, GitHub, itp.)

```dart
return CustomAlertDialog(
  title: title,
  content: Column(
    children: [
      LoginWidgetUserPass(
        username: username,
        pass: password,
        usernameMsg: usernameMsg,
        passMsg: passwordMsg,
        isInProgress: isInProgress,
        curOP: curOP,
        onLogin: onLogin,
        userFocusNode: userFocusNode,
      ),
      thirdAuthWidget(),
    ],
  ),
  onCancel: onDialogCancel,
  onSubmit: onLogin,
);
```

---

## 4. Metody uwierzytelniania

### 4.1. Logowanie natywne (username + password)

#### Przepływ:
1. Użytkownik wpisuje **login** i **hasło**
2. Walidacja lokalna (pola nie mogą być puste)
3. Wysłanie żądania HTTP POST do `/api/login`
4. Obsługa odpowiedzi

```dart
onLogin() async {
  // Walidacja
  if (username.text.isEmpty) {
    setState(() => usernameMsg = translate('Username missed'));
    return;
  }
  if (password.text.isEmpty) {
    setState(() => passwordMsg = translate('Password missed'));
    return;
  }
  
  curOP.value = 'rustdesk';
  setState(() => isInProgress = true);
  
  try {
    final resp = await gFFI.userModel.login(LoginRequest(
        username: username.text,
        password: password.text,
        id: await bind.mainGetMyId(),     // ID klienta RustDesk
        uuid: await bind.mainGetUuid(),   // UUID klienta
        autoLogin: true,
        type: HttpType.kAuthReqTypeAccount));  // "account"
    await handleLoginResponse(resp, true, close);
  } on RequestException catch (err) {
    passwordMsg = translate(err.cause);
  } catch (err) {
    passwordMsg = "Unknown Error: $err";
  }
}
```

### 4.2. Logowanie OIDC (trzecia strona — np. Google, GitHub)

#### Pobieranie opcji:
```dart
static Future<List<dynamic>> queryOidcLoginOptions() async {
  final url = await bind.mainGetApiServer();
  final resp = await http.get(Uri.parse('$url/api/login-options'));
  // Parsowanie opcji: 'oidc/google', 'oidc/github', itp.
  // lub format 'common-oidc/' z JSON
}
```

#### Przepływ OIDC:
1. Użytkownik klika przycisk dostawcy OIDC
2. Wywołanie `bind.mainAccountAuth(op: config.op, rememberMe: true)`
3. Rust-side inicjuje sesję OIDC (`OidcSession::account_auth()`)
4. Wysłanie POST do `/api/oidc/auth` → otrzymanie URL do autoryzacji
5. Otwarcie przeglądarki z URL autoryzacji
6. Periodyczne odpytywanie `/api/oidc/auth-query` co 1 sekundę (timeout: 3 minuty)
7. Po pomyślnej autoryzacji: zapisanie `access_token` i danych użytkownika

```rust
// src/hbbs_http/account.rs
fn auth_task(api_server: String, op: String, id: String, uuid: String, remember_me: bool) {
    // 1. POST /api/oidc/auth → uzyskanie code_url
    let auth_request_res = Self::auth(&api_server, &op, &id, &uuid);
    
    // 2. Polling GET /api/oidc/auth-query?code=...&id=...&uuid=...
    while keep_querying && elapsed < timeout {
        match Self::query(&api_server, &code_url.code, &id, &uuid) {
            Ok(HbbHttpResponse::Data(auth_body)) => {
                if auth_body.r#type == "access_token" {
                    // Sukces! Zapisz token.
                    LocalConfig::set_option("access_token", auth_body.access_token);
                    LocalConfig::set_option("user_info", ...);
                    return;
                }
            }
            // ...
        }
    }
}
```

Flutter UI monitoruje status co 1 sekundę i aktualizuje interfejs:
```dart
_beginQueryState() {
  _updateTimer = Timer.periodic(Duration(seconds: 1), (timer) {
    _updateState();
  });
}

_updateState() {
  bind.mainAccountAuthResult().then((result) {
    // Parsowanie stanu: state_msg, failed_msg, url, auth_body
  });
}
```

---

## 5. Model danych

### 5.1. `LoginRequest` — żądanie logowania
```dart
// flutter/lib/common/hbbs/hbbs.dart
class LoginRequest {
  String? username;           // Nazwa użytkownika
  String? password;           // Hasło
  String? id;                 // ID klienta RustDesk
  String? uuid;               // UUID klienta
  bool? autoLogin;            // Automatyczne logowanie
  String? type;               // Typ żądania (patrz HttpType)
  String? verificationCode;   // Kod weryfikacji email
  String? tfaCode;            // Kod 2FA
  String? secret;             // Sekret 2FA
}
```

### 5.2. `LoginResponse` — odpowiedź serwera
```dart
class LoginResponse {
  String? access_token;   // Token dostępu
  String? type;           // Typ odpowiedzi (patrz HttpType)
  String? tfa_type;       // Typ 2FA
  String? secret;         // Sekret (dla 2FA)
  UserPayload? user;      // Dane użytkownika
}
```

### 5.3. Typy żądań i odpowiedzi (`HttpType`)
```dart
class HttpType {
  // Typy żądań (Request)
  static const kAuthReqTypeAccount = "account";       // Login/hasło
  static const kAuthReqTypeMobile = "mobile";          // Logowanie mobilne
  static const kAuthReqTypeSMSCode = "sms_code";      // Kod SMS
  static const kAuthReqTypeEmailCode = "email_code";   // Kod e-mail
  static const kAuthReqTypeTfaCode = "tfa_code";       // Kod 2FA

  // Typy odpowiedzi (Response)
  static const kAuthResTypeToken = "access_token";     // Sukces → token
  static const kAuthResTypeEmailCheck = "email_check"; // Wymagana weryfikacja email
  static const kAuthResTypeTfaCheck = "tfa_check";     // Wymagana weryfikacja 2FA
}
```

### 5.4. `UserPayload` — dane użytkownika
```dart
class UserPayload {
  String name = '';
  String email = '';
  String note = '';
  String? verifier;
  UserStatus status;   // kDisabled, kNormal, kUnverified
  bool isAdmin = false;
}
```

---

## 6. `UserModel` — centralna klasa zarządzania stanem użytkownika

**Plik:** `flutter/lib/models/user_model.dart`

### 6.1. Stan reaktywny
```dart
class UserModel {
  final RxString userName = ''.obs;    // Obserwowalna nazwa użytkownika
  final RxBool isAdmin = false.obs;    // Czy administrator
  final RxString networkError = ''.obs; // Błąd sieci
  bool get isLogin => userName.isNotEmpty; // Czy zalogowany

  WeakReference<FFI> parent;
}
```

### 6.2. Metoda `login()`
```dart
Future<LoginResponse> login(LoginRequest loginRequest) async {
  final url = await bind.mainGetApiServer();
  final resp = await http.post(
    Uri.parse('$url/api/login'),
    body: jsonEncode(loginRequest.toJson()),
  );

  final body = jsonDecode(decode_http_response(resp));

  if (resp.statusCode != 200) {
    throw RequestException(resp.statusCode, body['error'] ?? '');
  }

  return getLoginResponseFromAuthBody(body);
}
```

### 6.3. Metoda `logOut()`
```dart
Future<void> logOut({String? apiServer}) async {
  final tag = gFFI.dialogManager.showLoading(translate('Waiting'));
  try {
    final url = apiServer ?? await bind.mainGetApiServer();
    await http.post(Uri.parse('$url/api/logout'),
        body: jsonEncode({
          'id': await bind.mainGetMyId(),
          'uuid': await bind.mainGetUuid(),
        }),
        headers: authHeaders)
        .timeout(Duration(seconds: 2));
  } finally {
    await reset(resetOther: true);  // Czyszczenie tokena i danych
  }
}
```

### 6.4. Metoda `reset()`
```dart
Future<void> reset({bool resetOther = false}) async {
  await bind.mainSetLocalOption(key: 'access_token', value: '');
  await bind.mainSetLocalOption(key: 'user_info', value: '');
  if (resetOther) {
    await gFFI.abModel.reset();    // Reset książki adresowej
    await gFFI.groupModel.reset(); // Reset grup
  }
  userName.value = '';
}
```

---

## 7. Obsługa odpowiedzi logowania (`handleLoginResponse`)

```dart
handleLoginResponse(LoginResponse resp, bool storeIfAccessToken,
    void Function([dynamic])? close) async {
  switch (resp.type) {
    case HttpType.kAuthResTypeToken:
      // ✅ SUKCES — otrzymano token
      if (resp.access_token != null) {
        if (storeIfAccessToken) {
          await bind.mainSetLocalOption(
              key: 'access_token', value: resp.access_token!);
          await bind.mainSetLocalOption(
              key: 'user_info', value: jsonEncode(resp.user ?? {}));
        }
        close(true);
        return;
      }
      break;

    case HttpType.kAuthResTypeEmailCheck:
      // 📧 Wymagana weryfikacja email
      close?.call(false);
      final res = await verificationCodeDialog(resp.user, resp.secret, true);
      if (res == true) {
        close?.call(true);
      }
      break;

    case HttpType.kAuthResTypeTfaCheck:
      // 🔐 Wymagana weryfikacja 2FA
      close?.call(false);
      if (resp.tfa_type == "totp") {
        // Weryfikacja TOTP (aplikacja authenticator)
        final res = await verificationCodeDialog(resp.user, resp.secret, false);
      } else {
        // Weryfikacja email
        final res = await verificationCodeDialog(resp.user, resp.secret, true);
      }
      break;

    default:
      passwordMsg = "Failed, bad response from server";
      break;
  }
}
```

---

## 8. Dialog weryfikacji kodu (`verificationCodeDialog`)

Wywoływany gdy serwer wymaga dodatkowej weryfikacji (email lub 2FA):

```dart
Future<bool?> verificationCodeDialog(
    UserPayload? user, String? secret, bool isEmailVerification) async {
  
  void onVerify() async {
    final resp = await gFFI.userModel.login(LoginRequest(
        verificationCode: code.text,
        tfaCode: isEmailVerification ? null : code.text,
        secret: secret,
        username: user?.name,
        id: await bind.mainGetMyId(),
        uuid: await bind.mainGetUuid(),
        autoLogin: autoLogin,
        type: HttpType.kAuthReqTypeEmailCode));

    switch (resp.type) {
      case HttpType.kAuthResTypeToken:
        if (resp.access_token != null) {
          await bind.mainSetLocalOption(
              key: 'access_token', value: resp.access_token!);
          close(true);
        }
        break;
    }
  }
}
```

---

## 9. Przechowywanie danych logowania

Dane uwierzytelniające przechowywane są **lokalnie** poprzez mechanizm `LocalOption`:

| Klucz | Opis | Przykład wartości |
|-------|------|-------------------|
| `access_token` | Token JWT/Bearer | `"eyJhbGciOiJ..."` |
| `user_info` | Dane użytkownika (JSON) | `{"name":"user","status":1}` |

Operacje zapisu:
```dart
await bind.mainSetLocalOption(key: 'access_token', value: resp.access_token!);
await bind.mainSetLocalOption(key: 'user_info', value: jsonEncode(resp.user ?? {}));
```

Operacje odczytu:
```dart
static Map<String, dynamic>? getLocalUserInfo() {
  final userInfo = bind.mainGetLocalOption(key: 'user_info');
  if (userInfo == '') return null;
  return json.decode(userInfo);
}
```

---

## 10. Odświeżanie stanu użytkownika

Przy starcie aplikacji lub po powrocie z tła, `UserModel` automatycznie odświeża dane:

```dart
void refreshCurrentUser() async {
  if (refreshingUser) return;
  refreshingUser = true;
  
  final url = await bind.mainGetApiServer();
  final response = await http.get(Uri.parse('$url/api/currentUser'),
      headers: getHttpHeaders());
  
  final user = UserPayload.fromJson(data);
  _parseAndUpdateUser(user);
  
  await updateOtherModels(); // Odświeżenie AB i grup
}
```

---

## 11. Aktualizacja zależnych modeli

Po pomyślnym logowaniu aktualizowane są powiązane modele:

```dart
static Future<void> updateOtherModels() async {
  await Future.wait([
    gFFI.abModel.pullAb(force: ForcePullAb.listAndCurrent, quiet: false),
    gFFI.groupModel.pull()
  ]);
}
```

Oznacza to, że:
- **Książka adresowa** (`AbModel`) jest synchronizowana z serwerem
- **Grupy** (`GroupModel`) są pobierane z serwera

---

## 12. Wylogowanie

### 12.1. Dialog potwierdzenia
```dart
void logOutConfirmDialog() {
  gFFI.dialogManager.show((setState, close, context) {
    submit() {
      close();
      gFFI.userModel.logOut();
    }
    return CustomAlertDialog(
      content: Text(translate("logout_tip")),
      actions: [
        dialogButton(translate("Cancel"), onPressed: close, isOutline: true),
        dialogButton(translate("OK"), onPressed: submit),
      ],
    );
  });
}
```

### 12.2. Proces wylogowania
1. Wysłanie POST do `/api/logout` z `id` i `uuid` klienta
2. Wyczyszczenie `access_token` i `user_info` z lokalnych opcji
3. Reset modelu książki adresowej i grup
4. Ustawienie `userName.value = ''` → reaktywne ukrycie elementów UI

---

## 13. Diagram przepływu logowania

```
┌─────────────────────────────────────────────────────────┐
│                   UŻYTKOWNIK                            │
│  (Klikn. "Zaloguj" w AB / Grupa / Ustawienia→Konto)    │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
              ┌─────────────────┐
              │  loginDialog()  │
              │  (login.dart)   │
              └───────┬─────────┘
                      │
          ┌───────────┼───────────────┐
          │                           │
          ▼                           ▼
┌──────────────────┐       ┌────────────────────┐
│ LoginWidgetUserPass│      │ LoginWidgetOP       │
│ (login + hasło)  │       │ (OIDC providers)   │
└────────┬─────────┘       └──────────┬─────────┘
         │                            │
         ▼                            ▼
┌──────────────────┐       ┌────────────────────┐
│ UserModel.login()│       │ OidcSession.auth() │
│ POST /api/login  │       │ POST /api/oidc/auth│
└────────┬─────────┘       └──────────┬─────────┘
         │                            │
         ▼                            ▼
┌──────────────────────────────────────────────┐
│            LoginResponse                      │
│  type: access_token | email_check | tfa_check │
└──────────────────┬───────────────────────────┘
                   │
     ┌─────────────┼────────────────┐
     │             │                │
     ▼             ▼                ▼
┌──────────┐ ┌──────────────┐ ┌────────────┐
│ ✅ Token │ │ 📧 Email     │ │ 🔐 2FA     │
│ → Zapisz │ │ Verification │ │ TOTP/Email │
│ → Zamknij│ │ → Dialog kod │ │ → Dialog   │
└──────────┘ └──────┬───────┘ └─────┬──────┘
                    │               │
                    ▼               ▼
              ┌──────────────────────────┐
              │ POST /api/login          │
              │ (z kodem weryfikacyjnym) │
              └────────────┬─────────────┘
                           │
                           ��
                   ┌───────────────┐
                   │ ✅ Token      │
                   │ → Zapisz      │
                   │ → Zamknij     │
                   └───────┬───────┘
                           │
                           ▼
              ┌────────────────────────┐
              │ updateOtherModels()    │
              │ • pullAb() — Książka   │
              │ • pull() — Grupy       │
              └────────────────────────┘
```

---

## 14. Endpointy API serwera

| Metoda | Endpoint | Opis |
|--------|----------|------|
| `GET` | `/api/login-options` | Pobranie dostępnych metod logowania (OIDC) |
| `POST` | `/api/login` | Logowanie (username/password, kody weryfikacji) |
| `POST` | `/api/logout` | Wylogowanie |
| `GET` | `/api/currentUser` | Odświeżenie danych zalogowanego użytkownika |
| `POST` | `/api/oidc/auth` | Inicjalizacja logowania OIDC |
| `GET` | `/api/oidc/auth-query` | Sprawdzenie statusu logowania OIDC (polling) |

---

## 15. Bezpieczeństwo

1. **Token dostępu** (`access_token`) jest przechowywany w lokalnych opcjach klienta (nie w jawnym tekście w pliku konfiguracyjnym)
2. **Hasło** jest przesyłane przez HTTPS do serwera API
3. **Wsparcie 2FA** — serwer może wymagać dodatkowego kodu TOTP lub weryfikacji email
4. **Auto-login** — pole `autoLogin: true` pozwala serwerowi na wydanie długoterminowego tokena
5. **Nagłówki autoryzacji** — po zalogowaniu, wszystkie żądania API zawierają `access_token` w nagłówkach HTTP
6. **Timeout OIDC** — sesja OIDC wygasa po 3 minutach braku autoryzacji

---

## 16. Kluczowe pliki źródłowe

| Plik | Opis |
|------|------|
| `flutter/lib/common/widgets/login.dart` | Dialog logowania, widgety UI, obsługa OIDC |
| `flutter/lib/models/user_model.dart` | Model użytkownika, metody login/logout |
| `flutter/lib/common/hbbs/hbbs.dart` | Definicje `HttpType`, `LoginRequest`, `LoginResponse`, `UserPayload` |
| `flutter/lib/desktop/pages/desktop_setting_page.dart` | Sekcja "Konto" w Ustawieniach |
| `flutter/lib/common/widgets/address_book.dart` | Przycisk logowania w Książce adresowej |
| `flutter/lib/common/widgets/my_group.dart` | Przycisk logowania w Mojej grupie |
| `src/hbbs_http/account.rs` | Logika OIDC po stronie Rust (sesja, auth, polling) |
| `src/ui_interface.rs` | Interfejs Rust↔Flutter dla wyników autoryzacji |
| `flutter/lib/utils/http_service.dart` | Warstwa HTTP (Flutter/Rust) |