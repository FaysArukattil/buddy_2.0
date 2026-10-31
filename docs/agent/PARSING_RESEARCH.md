# Buddy — Bank SMS Parsing Research

**Updated:** 2026-10-31  
**Purpose:** Per-region bank notification formats to drive `bank_rules.json` and country parsers.

---

## Default SMS App Packages (Any Region)

| Package | App | Notes |
|---|---|---|
| `com.google.android.apps.messaging` | Google Messages | Most common globally |
| `com.android.messaging` | AOSP Messaging | Stock Android |
| `com.samsung.android.messaging` | Samsung Messages | Samsung devices |
| `com.android.mms` | Generic MMS | Older Androids |
| `com.miui.mms` | MIUI Messages | Xiaomi/Poco/Redmi |
| `com.coloros.mms` | ColorOS Messages | OPPO/OnePlus |
| `com.oppo.mms` | OPPO Messages | OPPO |
| `com.vivo.mms` | vivo Messages | vivo devices |
| `com.realme.messaging` | Realme Messages | Realme |
| `com.oneplus.mms` | OnePlus Messages | OnePlus (OxygenOS) |
| `com.nothing.messaging` | Nothing Messages | Nothing Phone |
| `com.motorola.mms` | Motorola Messages | Motorola |
| `com.sonyericsson.conversations` | Sony Messages | Sony Xperia |
| `com.microsoft.msm` | Microsoft SMS Organizer | India/South Asia popular |
| `com.transsion.mobile.message` | Transsion Messages | Tecno/Itel/Infinix |
| `com.asus.message` | Asus Messages | Asus ZenFone |

---

## Overall Country Confidence Table

| Country | Code | Currency | Notification Channels | Confidence |
|---|---|---|---|---|
| India | IN | INR (₹) | SMS, Bank App, UPI Push | High (Production tested) |
| United States | US | USD ($) | Push, SMS (above threshold) | High |
| United Kingdom | GB | GBP (£) | Bank App Push, SMS | High |
| Germany | DE | EUR (€) | Bank App Push, SMS | High |
| France | FR | EUR (€) | Bank App Push, SMS | Medium |
| Spain | ES | EUR (€) | Bank App Push, SMS, Bizum | Medium |
| Italy | IT | EUR (€) | Bank App Push, SMS | Medium |
| United Arab Emirates | AE | AED | SMS, Bank App Push | High |
| Saudi Arabia | SA | SAR | SMS, Bank App Push | High |
| Nigeria | NG | NGN (₦) | SMS, Fintech Push | High |
| Kenya | KE | KES | SMS (M-Pesa), Bank Push | High |
| Singapore | SG | SGD (S$) | SMS, Push, PayNow | High |
| Brazil | BR | BRL (R$) | Push (PIX), SMS | High |
| Indonesia | ID | IDR (Rp) | Push, SMS, E-Wallet | High |
| Japan | JP | JPY (¥) | Email/Push, SMS | Medium |
| Pakistan | PK | PKR (Rs) | SMS, Wallet Push | Medium |
| Bangladesh | BD | BDT (৳) | SMS (bKash/Nagad) | Medium |
| Philippines | PH | PHP (₱) | SMS, GCash/Maya Push | High |
| Malaysia | MY | MYR (RM) | SMS, Bank Push, DuitNow | Medium |
| South Africa | ZA | ZAR (R) | SMS, Bank App Push | High |
| Turkey | TR | TRY (₺) | SMS, Bank Push | Medium |
| Mexico | MX | MXN ($) | Push, SMS | Medium |
| Egypt | EG | EGP | SMS, InstaPay Push | Medium |
| Australia | AU | AUD ($) | Bank Push, SMS | Medium |
| New Zealand | NZ | NZD ($) | Bank Push, SMS | Low |
| Kuwait / Bahrain / Oman | KW/BH/OM | KWD/BHD/OMR | SMS, Bank Push (3 decimals) | Medium |
| Others (40+ countries) | Various | Various | SMS / Bank Push | Medium / Low |

---

## India (IN) — Baseline ✅

**Currency:** INR (₹), `en_IN` locale, Indian numbering (1,23,456)  
**Confidence:** High (existing production parser)

### Source Packages
- All SMS packages above (bank SMS → default SMS app)
- UPI apps: `com.phonepe.app`, `com.google.android.apps.nbu.paisa.user`, `net.one97.paytm`, `in.org.npci.upiapp`, `com.dreamplug.androidapp` (CRED), `com.mobikwik_new`, `com.freecharge.android`
- Bank apps: `com.sbi.lotusintouch`, `com.csam.icici.bank.imobile`, `com.snapwork.hdfc`, `com.axis.mobile`, `com.fedmobile`, `com.canara.mobility`, etc. (full list in NotificationListener.kt)

### Sender / Title Patterns
- Sender: `SBIINB`, `HDFCBK`, `ICICIB`, `AXISBK`, `FEDBK`, `CANBNK`, `KOTAKB`, `VM-SBIINB`, `TM-HDFCBK`, etc.
- Title: Account notification, Transaction Alert, HDFC Bank, SBI, etc.

### Amount Patterns
- Prefix: `Rs.500`, `Rs 500`, `INR 500`, `₹500`, `₹ 500`
- Suffix: `500.00 INR`, `6500.00` (bare, contextual)
- Comma-separated Indian numbering: `1,23,456.00`

### Debit Keywords
`debited`, `debited by`, `debited for`, `debited with`, `withdrawn`, `paid to`, `paid at`, `payment of`, `payment to`, `spent`, `transferred to`, `sent`, `deducted`, `charged`, `utilized`, `successfully executed`, `mandate executed`, `auto-debited`, `autopay`, `auto pay`

### Credit Keywords
`credited`, `credited with`, `credited by`, `deposited`, `received from`, `received in`, `you received`, `sent you`, `paid you`, `refund`, `reversal`, `cashback credited`, `salary credited`

### Balance Patterns (exclude from amount)
`Bal`, `Balance`, `Avl Bal`, `Avbl Bal`, `Avail Bal`, `Available Bal`, `A/c Bal`

### Ignore Patterns (PROMOTIONAL_AND_SPAM_KEYWORDS — see NotificationListener.kt)
OTP, KYC, loan offer, pre-approved, congratulations, get up to, win, discount, promo, bill due, payment request, failed, declined, etc.

### Sample SMS
```
# SBI UPI Debit
Dear SBI User, your A/c X1690-debited by Rs 100.0 on 17Jan23 transfer to SANTHOSH KUMAR M Ref No 301786029918. If not done by u, fwd this SMS to 9223008333/Call 1800111109 to block UPI -SBI.

# Federal Bank ATM
Rs 3000 withdrawn@ DAHISAR on 03OCT26 10:34 Bal Rs 32839.08 Ref 627610749779. Not you? Call 18004251199/ SMS NO 1549 to 9895088888 -Federal Bank.

# Canara Bank Credit (UPI)
Dear Customer, Acct XXXX8585 credited with INR 300.00 on 19/09/26 from SUFAIRA VAZH; UPI:129847355238; Bal INR 316.35-CanaraBank.

# SBI UPI Debit (bare amount)
Dear UPI user A/C X7495 debited by 6500.00 on date 01Oct26 trf to KUNHAYAMMU A Refno 627420891569 If not u? call-1800111109 for other services-18001234-SBI

# Netflix Mandate
Dear Customer, Your mandate with ref no- be453b0999304fe59da234f67bc786c6@okaxis registered against Netflix for Rs 199.00 successfully executed on 28-07-2026 07:41:34. TXN Ref No -253323902096- Federal Bank
```

---

## Pakistan (PK)

**Currency:** PKR (Rs / PKR), `en_PK` locale  
**Confidence:** Medium

### Source Packages
- Default SMS app (same global list above)
- Bank apps: `com.hbl.android` (HBL), `com.ubldigital.android` (UBL), `com.mcb.mcbmobilebanking`, `com.alfalahbranchless` (Bank Alfalah), `com.meezan.meezanbank`, `com.askaribank.askarimobileapp`, `com.jsbl.jsbank`, `com.bankislami.mobilebanking`, `com.faysal.mobile`, `com.nbp.nbpmobile`
- Fintech: `pk.jazzcash.android.application` (JazzCash), `pk.easypaisa.easypaisa` (EasyPaisa)

### Sender / Title Patterns
- Sender: `HBL`, `UBL`, `MCB`, `ALFALAH`, `MEEZAN`, `ASKARI`, `JSBL`, `NBP`
- Title: "HBL Transaction Alert", "UBL Account Notification"

### Amount Patterns
- Prefix: `Rs.5,000`, `PKR 5000`, `Rs 5,000`
- No ₹ (that's India only); PKR written as Rs or PKR
- Decimal separator: `.` (period), thousands: `,`

### Debit Keywords
`debited`, `withdrawn`, `paid`, `transferred`, `purchase`, `debit`, `payment made`, `sent`

### Credit Keywords
`credited`, `received`, `deposited`, `credit`, `transferred to your account`, `salary`

### Balance Keywords
`Balance`, `Bal`, `Available Balance`, `Avl Bal`

### Ignore Patterns
OTP, PIN, verification, promo offer, congratulations, due date, payment reminder

### Sample SMS
```
HBL: Rs.5,000/- has been debited from A/c XXXX1234 on 31-Oct-2026 at POS. Avl Bal: Rs.24,500/-. Not you? Call 111-111-425.

UBL: Your A/c XXXX5678 has been credited with PKR 20,000 on 31-Oct-26. Available Balance: PKR 45,000. UBL Mobile: 0311-8258282.

JazzCash: PKR 500 sent to 03001234567. Transaction ID: T2610312345. Balance: PKR 1,500.
```

---

## Bangladesh (BD)

**Currency:** BDT (৳ / Tk / BDT), `bn_BD` locale  
**Confidence:** Medium

### Source Packages
- Default SMS app
- Bank apps: `com.dutchbanglabank.rocket` (DBBL/Rocket), `com.brac.bank.mobile` (BRAC Bank), `com.islamibank.ibank` (Islami Bank), `com.citybank.citytouch` (City Bank), `com.dutchbanglabankltd.nexus` (Dutch-Bangla Nexus)
- MFS: `com.sslcommerz.bkash` (bKash), `com.jaxara.nagad` (Nagad), `com.tmoney.tmoneybd` (TeleCash)

### Amount Patterns
- `Tk.5,000`, `BDT 5000`, `৳500`
- Thousands: `,`; Decimal: `.`

### Debit Keywords
`debited`, `withdrawn`, `paid`, `sent`, `deducted`, `transferred`, `payment`, `purchase`

### Credit Keywords
`credited`, `received`, `deposited`, `Add Money`, `Cash In`

### Sample SMS
```
bKash: Tk 500.00 sent to 01712345678 from your bKash account. Fee Tk 5.00. Balance: Tk 1,234.56. TrxID AB2610312345.

DBBL Rocket: BDT 2000 received in your Rocket account 01912345678. Balance BDT 5,432.10.

BRAC Bank: BDT 10,000 debited from A/c XXXX1234 via UBL on 31-Oct-2026. Avl Bal: BDT 25,000.
```

---

## Sri Lanka (LK)

**Currency:** LKR (Rs / LKR), `si_LK` locale  
**Confidence:** Medium

### Source Packages
- Default SMS app
- Bank apps: `com.combank.comcash` (Commercial Bank), `lk.sdb.mobile` (Sampath Bank), `com.hnb.mobile` (HNB), `com.peoples.bank.mobile` (People's Bank), `lk.nsb.nsbmobile`, `com.boc.mobilePay` (Bank of Ceylon)
- Wallet: `com.lk.frimi.mobile` (Frimi by People's Bank)

### Amount Patterns
- `Rs.5,000.00`, `LKR 5000`, `Rs 5,000`

### Debit Keywords
`debited`, `withdrawn`, `payment`, `transferred`, `purchase`, `charged`

### Credit Keywords
`credited`, `received`, `deposited`, `transferred to account`

### Sample SMS
```
Commercial Bank: Your A/c XXXX1234 was debited by LKR 5,000.00 on 31/10/2026. Avl Bal: LKR 45,000.00. Call 0112353353 if not done by you.

Sampath Bank: Rs.3,500.00 credited to your a/c XXXX5678 via SLIPS/CEFT on 31/10/2026. Avail Bal: Rs.28,500.00.
```

---

## Nepal (NP)

**Currency:** NPR (Rs / NPR / रु), `ne_NP` locale  
**Confidence:** Low-Medium

### Source Packages
- Default SMS app
- Bank apps: `com.nabil.nabilmobile`, `com.nicasia.nicasiabank`, `com.kumaribank.mobile`, `com.laxmibank.laxmisunrise`, `com.everestbank.everestmobile`
- Wallet: `np.com.fonepay.merchant` (FonePay), `np.com.esewa.esewa` (eSewa), `np.khalti.app` (Khalti)

### Amount Patterns
- `Rs.5,000`, `NPR 5000`, `रु 500`

### Sample SMS
```
Nabil Bank: Rs.5,000 debited from A/c XXXX1234. Avl Bal Rs.10,000. Ref 123456. If not you call 01-4445555.

eSewa: NPR 500 sent to 9801234567. TxnId: eSw123456. Balance NPR 1,500.
```

---

## United Arab Emirates (AE)

**Currency:** AED (AED / د.إ), `en_AE` locale (or `ar_AE`)  
**Confidence:** Medium

### Source Packages
- Default SMS app
- Bank apps: `com.emiratesnbd.enbd` (Emirates NBD), `com.adcb.adcbmobile` (ADCB), `ae.fab.mobile` (First Abu Dhabi Bank / FAB), `com.mashreqmobile` (Mashreq), `com.adib.mobile` (ADIB), `com.dib.mobile` (Dubai Islamic Bank), `com.cbd.mobile` (Commercial Bank of Dubai), `com.rakbank.mobile` (RAK Bank), `com.enbd.smile` (ENBD Smile)

### Amount Patterns
- `AED 1,500.00`, `AED1500`, `د.إ 500`
- Thousands: `,`; Decimal: `.`

### Debit Keywords
`debited`, `withdrawn`, `purchase`, `payment`, `spent`, `transferred`, `POS`, `ATM withdrawal`, `debit`

### Credit Keywords
`credited`, `received`, `deposited`, `salary`, `transfer received`

### Balance Keywords
`Available Balance`, `Avl Bal`, `Balance`

### Ignore Patterns
OTP, offer, congratulations, apply now, loan offer, reminder, due date, failed

### Sample SMS
```
Emirates NBD: AED 1,500.00 has been debited from your account XXXX1234 on 31/10/2026 at [Merchant]. Available Balance: AED 10,000.00. SMS STOP to 4455 to opt out.

FAB: AED 3,000 credited to your Account XXXX5678 on 31-Oct-26. Balance: AED 25,000. Contact 600 52 2000 for queries.

Mashreq: Your Card XXXX1234 was used for AED 250.00 at CARREFOUR on 31/10/2026. Available limit: AED 15,000.00.
```

---

## Saudi Arabia (SA)

**Currency:** SAR (SAR / ر.س), `en_SA` locale (or `ar_SA`)  
**Confidence:** Medium

### Source Packages
- Default SMS app
- Bank apps: `com.alrajhibank.android` (Al Rajhi Bank), `com.ncb.alahli` (SNB / Al Ahli), `com.riyadhbank.rb` (Riyad Bank), `com.sabb.mobile` (SABB / HSBC Saudi), `com.alinmabank.mobile` (Alinma Bank), `com.banksadhan.banksadhan` (Bank AlBilad), `com.alawwal.mobilebanking` (Arab National Bank)

### Amount Patterns
- `SAR 1,500.00`, `SR 500`, `ر.س 500`

### Debit Keywords
`debited`, `withdrawn`, `purchase`, `paid`, `POS`, `ATM`, `transferred`

### Credit Keywords
`credited`, `received`, `salary`, `deposited`

### Sample SMS
```
Al Rajhi: SAR 500.00 debited from your account XXXX1234 via POS on 31/10/2026. Available Balance: SAR 10,000.00.

SNB: SAR 5,000 credited to your account XXXX5678 on 31-Oct-2026. Balance: SAR 30,000. Call 920002470 for help.
```

---

## Qatar (QA), Kuwait (KW), Bahrain (BH), Oman (OM)

**Currencies:** QAR, KWD, BHD, OMR  
**Confidence:** Medium (similar format to UAE/SA)

### Amount Patterns
- QAR: `QAR 500`, `QR 500`
- KWD: `KWD 50.000` (3 decimal places!), `KD 50`
- BHD: `BHD 50.000` (3 decimal places!), `BD 50`
- OMR: `OMR 50.000` (3 decimal places!), `RO 50`

> **Important:** KWD, BHD, OMR use 3 decimal places (dinars/baizas). Parser must handle correctly.

### Source Packages (Qatar example)
- `com.qatarnationalbank.qnbmobile` (QNB), `com.cbq.cbqgo` (CBQ), `com.dohacommunity.bank`

### Sample SMS
```
QNB: QAR 500.00 debited from your account XXXX1234. Avail Bal: QAR 10,000.00. Txn Ref: QNB123456.

KFH Kuwait: KWD 50.000 credited to your account XXXX5678. Available Balance: KWD 500.000.

BHD Bank: BHD 25.000 debited via POS. Balance BHD 1,000.000. Ref 123456.
```

---

## Nigeria (NG)

**Currency:** NGN (₦), `en_NG` locale  
**Confidence:** Medium-High

### Source Packages
- Default SMS app
- Bank apps: `com.firstbank.firstmobile` (First Bank), `com.accessbank.accessmobile` (Access Bank), `com.gtb.mobilebanking` (GT Bank), `com.zenith.bank.mobile` (Zenith Bank), `com.uba.mobilebanking` (UBA), `com.stanbic.mobile` (Stanbic IBTC), `com.fcmb.mobile` (FCMB), `com.keystone.mobilebanking`, `ng.opay.apps` (OPay), `io.kuda.android` (Kuda), `moniepoint.hq.agent` (Moniepoint)

### Amount Patterns
- `₦5,000.00`, `NGN 5000`, `5000NGN`

### Debit Keywords
`debited`, `withdrawn`, `purchase`, `payment`, `POS`, `ATM`, `transferred`, `sent`, `charged`

### Credit Keywords
`credited`, `received`, `deposited`, `transfer received`, `salary`

### Sample SMS
```
GTBank: Your account XXXX1234 has been debited with NGN5,000.00 on 31-Oct-2026 at POS. Avl Bal: NGN45,000.00. Call 07003000424 if not you.

Access Bank: ₦20,000 credited to your account XXXX5678 via transfer on 31/10/2026. Balance: ₦65,000. Ref: ACC123456.

OPay: ₦500 debit. Merchant: UBER EATS. Balance: ₦1,500. Time: 14:32.
```

---

## Kenya (KE)

**Currency:** KES (KSh / KES), `sw_KE` locale  
**Confidence:** Medium-High (M-Pesa dominant)

### Source Packages
- Default SMS app
- `com.safaricom.mpesa` (M-Pesa — dominant)
- Bank apps: `com.kcb.bankapp` (KCB), `com.equity.mobile` (Equity), `com.absa.ke.mobile` (Absa Kenya), `com.stanbic.ke.mobile` (Stanbic Kenya), `com.cooperative.bank` (Co-operative Bank)

### Amount Patterns
- `KSh1,500.00`, `KES 1500`, `Ksh 500`

### Debit Keywords
`sent`, `paid`, `withdrawn`, `buy goods`, `paybill`, `payment`, `transferred`

### Credit Keywords
`received`, `deposited`, `credited`, `money in`

### M-Pesa specific (very common)
- Sender: `MPESA` / title: `M-Pesa`
- Format: `[name] sent you Ksh[amount]` or `You have received Ksh[amount] from [name]`
- Confirmation: `[Name] has received Ksh[amount] from your M-PESA account`

### Sample SMS
```
M-PESA: You have received Ksh1,500.00 from John Doe 0712345678 on 31/10/26 at 2:32 PM. New M-PESA balance is Ksh3,000.00.

M-PESA: Ksh500.00 sent to 0722345678 Jane Smith on 31/10/26 at 3:15 PM. Transaction cost Ksh6.00. New balance Ksh2,494.00.

KCB: KES 10,000 credited to your account XXXX1234 on 31-Oct-2026. Available Balance: KES 45,000.
```

---

## South Africa (ZA)

**Currency:** ZAR (R), `en_ZA` locale  
**Confidence:** Medium

### Source Packages
- Default SMS app
- Bank apps: `za.co.fnb.mobile` (FNB), `za.co.absa.mobile` (Absa), `za.co.standardbank.mobile` (Standard Bank), `za.co.nedbank.mobile` (Nedbank), `com.capitec.bank.mobile` (Capitec)

### Amount Patterns
- `R1,500.00`, `ZAR 1500`, `R 500`

### Debit Keywords
`debited`, `purchased`, `payment made`, `withdrawn`, `transferred`, `spent`

### Credit Keywords
`credited`, `received`, `deposited`, `salary`

### Sample SMS
```
FNB: R1,500.00 has been debited from cheque account XXXX1234 on 31-10-2026 for POS purchase. Available Balance: R10,000.00.

Capitec: R5,000 received from Jane Smith to your account. Balance: R12,000. 

Standard Bank: R2,500.00 credited to account XXXX5678 via EFT on 31/10/2026. Avail Bal: R18,500.00.
```

---

## Ghana (GH)

**Currency:** GHS (GH₵ / GHS / ¢), `en_GH` locale  
**Confidence:** Medium

### Source Packages
- Default SMS app
- `com.mtn.momo.ghana` (MTN MoMo — dominant)
- `com.abcbank.mobile` (ABC Bank), `com.gcb.mobile` (GCB Bank), `com.stanbic.gh.mobile`

### Sample SMS
```
MTN MoMo: GHS50.00 has been deducted from your MoMo account for payment to MerchantName. Balance: GHS150.00. Ref: 12345.

GCB Bank: GH₵5,000 credited to your account XXXX1234. Available Balance: GH₵15,000. Txn Ref: GCB123456.
```

---

## Tanzania (TZ)

**Currency:** TZS (TSh / TZS), `sw_TZ` locale  
**Confidence:** Low-Medium

### Source Packages
- Default SMS app
- `com.vodacom.mpesa.tz` (M-Pesa Tanzania), `com.airtel.money.tz` (Airtel Money), `com.tigo.tigopesa`

### Sample SMS
```
M-Pesa: TSh10,000 imetumwa kwa 0712345678. Salio lako jipya: TSh25,000. Namba ya Muamala: ABC123.

CRDB Bank: TZS 50,000 credited to account XXXX1234 on 31/10/2026. Balance: TZS 250,000.
```

---

## Egypt (EG)

**Currency:** EGP (EGP / ج.م), `ar_EG` locale (or `en_EG`)  
**Confidence:** Low-Medium

### Source Packages
- Default SMS app
- `com.vodafone.eg.mycash` (Vodafone Cash), `com.instapay.eg` (InstaPay)
- Bank apps: `com.cib.cibengage` (CIB), `com.qnb.egypt` (QNB Egypt), `com.bankaudi.mobile`

### Amount Patterns
- `EGP 1,500.00`, `ج.م 500`

### Sample SMS
```
CIB: EGP 2,000.00 debited from your account XXXX1234 on 31/10/2026. Available Balance: EGP 15,000.00. If not done by you call 19666.

Vodafone Cash: EGP 500 sent to 0101234567. Your balance is EGP 1,000.
```

---

## United Kingdom (GB)

**Currency:** GBP (£), `en_GB` locale  
**Confidence:** Medium-High

### Source Packages
- Default SMS app
- Bank apps: `com.barclays.android.barclaysmobilebanking` (Barclays), `com.rbs.mobile.android.ubn` (RBS/NatWest), `com.lloyds.mobile.android` (Lloyds Bank), `com.hsbc.hsbcuksb` (HSBC UK), `com.santander.retail` (Santander UK)
- Challenger: `com.monzo.android` (Monzo), `com.revolut.revolut` (Revolut), `uk.co.starlingbank` (Starling Bank)

### Amount Patterns
- `£1,500.00`, `GBP 1500`

### Debit Keywords
`debited`, `payment`, `purchase`, `spent`, `transferred`, `withdrawn`, `taken`

### Credit Keywords
`credited`, `received`, `deposited`, `paid in`, `salary`

### Sample SMS
```
Barclays: £250.00 was taken from your account XXXX1234 on 31 Oct 2026. Balance: £1,500.00. Call 03457 345 345 if not you.

Monzo: You paid £15.00 to Tesco on 31 Oct 2026. Your balance is £500.00.

HSBC UK: £1,000.00 has been credited to your account XXXX5678. Available balance: £5,000.00.
```

---

## Germany (DE)

**Currency:** EUR (€), `de_DE` locale  
**Important:** European decimal format — `.` for thousands, `,` for decimals (1.234,56)  
**Confidence:** Medium

### Source Packages
- Default SMS app
- Bank apps: `de.consorsbank` (Consorsbank), `de.dkb.productsapp` (DKB), `de.commerzbank.banking.app` (Commerzbank), `de.ing.banking` (ING), `de.postbank.finanzassistent` (Postbank)

### Amount Patterns
- `1.234,56 €`, `€ 500,00`, `500 EUR`
- **Parse correctly:** dot=thousands separator, comma=decimal

### Debit Keywords
`wurde belastet`, `abgebucht`, `bezahlt`, `überweisung ausgeführt`, `abhebung`, `belastung`, `zahlung` (German terms)

### Credit Keywords
`wurde gutgeschrieben`, `eingegangen`, `gutschrift`, `überweisung erhalten` (German terms)

### Sample SMS
```
DKB: Ihre Karte XXXX1234 wurde am 31.10.2026 mit 1.234,56 € belastet. Verfügbarer Betrag: 5.000,00 €.

ING: Gutschrift von 2.000,00 € auf Ihr Konto XXXX5678 am 31.10.2026. Kontostand: 10.000,00 €.
```

---

## France (FR)

**Currency:** EUR (€), `fr_FR` locale  
**Important:** European decimal format — space for thousands, `,` for decimals (1 234,56)  
**Confidence:** Medium

### Sample SMS
```
BNP Paribas: Votre compte XXXX1234 a été débité de 500,00 € le 31/10/2026. Solde disponible: 2 500,00 €.

Crédit Agricole: Vous avez reçu un virement de 1 000,00 € le 31/10/2026. Solde: 5 000,00 €.
```

---

## Spain (ES)

**Currency:** EUR (€), `es_ES` locale  
**Important:** European decimal format  
**Confidence:** Medium

### Source Packages
- `com.bankia.mobile` (CaixaBank/Bankia), `com.banco.sabadell` (Sabadell), `com.santander.app` (Santander), `es.openbank.mobile` (OpenBank)

### Sample SMS
```
CaixaBank: Se ha realizado un cargo de 150,00 € en tu cuenta XXXX1234 el 31/10/2026. Saldo disponible: 3.500,00 €.
```

---

## Netherlands (NL)

**Currency:** EUR (€), `nl_NL` locale  
**Confidence:** Medium

### Source Packages
- `nl.abn.amrobanking.mobile` (ABN AMRO), `nl.rabobank.mobile` (Rabobank), `com.ing.mobile` (ING Netherlands)

---

## Italy (IT)

**Currency:** EUR (€), `it_IT` locale  
**Confidence:** Low-Medium

### Source Packages
- `com.unicredit.mobile.android` (UniCredit), `it.ingdirect.app` (ING Italy), `com.intesasanpaolo.banking` (Intesa Sanpaolo)

---

## Turkey (TR)

**Currency:** TRY (₺), `tr_TR` locale  
**Confidence:** Medium

### Source Packages
- Default SMS app
- Bank apps: `com.garanti.gobile` (Garanti BBVA), `com.isbank.isbankmobileapp` (İş Bankası), `com.ziraatbank.mobile` (Ziraat Bankası), `com.akbank.android.apps.akbank` (Akbank), `com.ykb.android` (Yapı Kredi)

### Amount Patterns
- `1.234,56 TL`, `₺ 500,00`, `500 TRY`
- Turkish format: `.` thousands, `,` decimals

### Debit Keywords
`hesabınızdan`, `ödeme`, `borçlandırıldı`, `alındı`, `çekildi`, `aktarıldı` (Turkish)

### Credit Keywords
`alacaklandırıldı`, `yatırıldı`, `gelen transfer`, `hesabınıza` (Turkish)

### Sample SMS
```
Garanti BBVA: 31.10.2026 tarihinde XXXX1234 nolu hesabınızdan 1.500,00 TL tutarında işlem yapıldı. Bakiye: 10.000,00 TL.

İş Bankası: Hesabınıza 5.000,00 TL havale alındı. Bakiye: 25.000,00 TL. Gönderen: John Doe.
```

---

## United States (US)

**Currency:** USD ($), `en_US` locale  
**Confidence:** Medium-Low (US banks rely more on push notifications from apps than SMS)

### Source Packages
- Default SMS app
- Bank apps: `com.chase.mobile` (Chase), `com.bankofamerica.boamobilebanking` (Bank of America), `com.wellsfargo.mobile` (Wells Fargo), `com.usaa.mobile.android.usaa` (USAA), `com.citibank.mobile` (Citi US)
- Fintech: `com.venmo` (Venmo), `com.squareup.cash` (Cash App), `com.paypal.android.p2pmobile` (PayPal)

### Amount Patterns
- `$1,500.00`, `USD 1500`

### Debit Keywords
`was charged`, `was debited`, `purchase`, `payment`, `withdrawn`, `transferred`, `sent`

### Credit Keywords
`was credited`, `received`, `deposited`, `direct deposit`, `transfer received`

### Sample SMS
```
Chase: A charge of $250.00 was made to your account ending in 1234 on Oct 31, 2026. Balance: $1,500.00. Call 1-800-935-9935 if not you.

Bank of America: $1,000.00 was deposited to your account ending in 5678 on Oct 31, 2026. Balance: $5,000.00.

Venmo: You paid John Smith $25.00 for dinner.
```

---

## Canada (CA)

**Currency:** CAD ($ / CAD), `en_CA` locale  
**Confidence:** Medium-Low

### Source Packages
- Default SMS app
- Bank apps: `ca.rbc.mobile.rbcmobile` (RBC), `com.td.tdbfg` (TD), `com.bmo.mobile` (BMO), `com.scotiabank.mobile` (Scotiabank), `com.cibc.mobile` (CIBC)

### Amount Patterns
- `$1,500.00`, `CAD 1,500.00`

### Sample SMS
```
RBC: A transaction of $500.00 has been debited from your account ending 1234 on Oct 31, 2026. Balance: $2,500.00.

TD: $1,000.00 was deposited to account ending 5678 on 2026-10-31. Available Balance: $10,000.00.
```

---

## Mexico (MX)

**Currency:** MXN ($ / MXN), `es_MX` locale  
**Confidence:** Medium

### Source Packages
- Default SMS app
- Bank apps: `com.bancomer.banamex` (BBVA), `mx.banamex.app` (Citibanamex), `com.hsbc.hsbcmx` (HSBC Mexico), `mx.banorte.mobile`, `com.banregio.banregio`

### Amount Patterns
- `$1,500.00`, `MXN 1,500.00`

### Debit Keywords
`se realizó un cargo`, `débito`, `retiro`, `pago`, `transferencia` (Spanish)

### Credit Keywords
`abono`, `depósito`, `crédito`, `transferencia recibida` (Spanish)

### Sample SMS
```
BBVA: Se realizó un cargo de $1,500.00 a tu cuenta XXXX1234 el 31/10/2026. Saldo disponible: $8,500.00.

Citibanamex: Se acreditaron $5,000.00 a tu cuenta XXXX5678. Saldo: $20,000.00. Ref 123456.
```

---

## Brazil (BR)

**Currency:** BRL (R$), `pt_BR` locale  
**Important:** Brazilian format — `.` thousands, `,` decimals (R$ 1.234,56)  
**Confidence:** Medium

### Source Packages
- Default SMS app
- Bank apps: `com.bradesco.prime` (Bradesco), `com.itau.bankapp` (Itaú), `br.com.bb.android` (Banco do Brasil), `com.nu.productionapp` (Nubank), `com.santander.br.superapp`
- PIX payment system (widely used)

### Amount Patterns
- `R$ 1.234,56`, `BRL 1234`

### Debit Keywords
`debitado`, `compra`, `pagamento`, `transferência enviada`, `pix enviado`, `sacado`, `retirado`

### Credit Keywords
`creditado`, `recebido`, `depósito`, `pix recebido`, `transferência recebida`, `salário`

### Sample SMS
```
Nubank: R$ 150,00 foi cobrado no seu cartão. Saldo disponível: R$ 2.000,00.

Itaú: Débito de R$ 1.500,00 na conta XXXX1234 em 31/10/2026. Saldo: R$ 10.000,00. Ref 123456.

Banco do Brasil: Pix de R$ 500,00 recebido de João Silva. Saldo: R$ 3.000,00.
```

---

## Argentina (AR)

**Currency:** ARS ($), `es_AR` locale  
**Confidence:** Low-Medium

### Source Packages
- Default SMS app
- `ar.com.mercadolibre.mercanet` (Mercado Pago — dominant), `com.naranjax.android` (Naranja X)
- Bank apps: `com.bancogalicia.android` (Galicia), `com.hsbc.ar.mobile`, `com.macro.android`

### Amount Patterns
- `$1.500,00` (dot thousands, comma decimal), `ARS 1500`

### Sample SMS
```
Mercado Pago: Transferiste $5.000,00 a Juan Pérez. Saldo: $12.000,00. Código de operación: 123456.

Galicia: Se acreditaron $10.000,00 en tu cuenta XXXX1234. Saldo: $45.000,00.
```

---

## Colombia (CO)

**Currency:** COP ($), `es_CO` locale  
**Confidence:** Low-Medium

### Amount Patterns
- `$150.000` (dot thousands, no decimals common for COP), `COP 150000`

### Source Packages
- Default SMS app
- `com.bancolombia.mobile` (Bancolombia), `com.nequi.app` (Nequi), `com.daviplata.app` (DaviPlata)

### Sample SMS
```
Nequi: Transferiste $50.000 a 3001234567. Tu saldo es $200.000. 31/10/2026.

Bancolombia: Su cuenta XXXX1234 fue debitada por $150.000 el 31/10/2026. Saldo disponible: $800.000.
```

---

## Japan (JP)

**Currency:** JPY (¥ / 円), `ja_JP` locale  
**Important:** JPY has 0 decimal places  
**Confidence:** Low-Medium (Japanese SMS banking less common; apps more prevalent)

### Amount Patterns
- `¥5,000`, `5,000円`, `JPY 5000`
- **No decimals** — parser must set decimalDigits=0

### Source Packages
- Default SMS app
- Bank apps: `jp.co.rakuten_bank.android` (Rakuten Bank), `jp.co.smbc.smbc_direct` (SMBC), `jp.co.mizuhobank.android.mizuhort` (Mizuho), `jp.co.ufj.mbs` (MUFG)
- Konbini/PayPay: `jp.ne.paypay.android.nativeapp` (PayPay)

### Sample SMS
```
楽天銀行: 口座XXXX1234から¥5,000が引き落とされました。残高：¥50,000。2026/10/31。

PayPay: ¥500を支払いました。PayPay残高：¥1,500。
```

---

## South Korea (KR)

**Currency:** KRW (₩), `ko_KR` locale  
**Important:** KRW has 0 decimal places  
**Confidence:** Low-Medium

### Amount Patterns
- `₩50,000`, `50,000원`, `KRW 50000`

### Source Packages
- Default SMS app
- Bank apps: `com.kakaobank.channel` (Kakao Bank), `kr.co.kbstar.kbbank` (KB Bank), `com.shinhan.sbanking` (Shinhan Bank), `com.smobile.presentlife` (Woori Bank)
- `com.kakaocorp.talk` (KakaoTalk Pay)

### Sample SMS
```
카카오뱅크: 50,000원이 출금되었습니다. 잔액: 500,000원. 2026.10.31 14:32.

신한은행: 계좌 XXXX1234에서 ₩100,000 이체 완료. 잔액 ₩1,500,000.
```

---

## Indonesia (ID)

**Currency:** IDR (Rp), `id_ID` locale  
**Important:** IDR has 0 decimal places; large amounts (50.000 = 50,000 IDR)  
**Note:** Indonesian format: `.` for thousands, no decimal separator for IDR  
**Confidence:** Medium

### Amount Patterns
- `Rp50.000`, `Rp 100.000`, `IDR 50000`

### Source Packages
- Default SMS app
- Bank apps: `id.co.bca.mobile.banking.myBCA` (BCA), `id.co.mandiri.retail.android` (Bank Mandiri), `id.co.bni.mobilebanking` (BNI), `id.co.bri.brimobilenew` (BRI)
- E-wallets: `com.gojek.app` (GoPay), `com.tokopedia.tkpd` (Tokopedia), `id.co.linkaja.app` (LinkAja), `com.danamon.mobile` (OVO)

### Sample SMS
```
BCA: Rek XXXX1234 Db Rp100.000 tgl 31/10/26 ATM. Saldo Rp5.000.000. Info: 1500888.

Bank Mandiri: Debet Rp250.000 tgl 31-10-2026 di ATM Mandiri. Saldo: Rp10.000.000.

GoPay: Kamu membayar Rp50.000 ke Gojek Driver. Saldo GoPay: Rp150.000.
```

---

## Philippines (PH)

**Currency:** PHP (₱), `en_PH` locale  
**Confidence:** Medium

### Source Packages
- Default SMS app
- Bank apps: `com.bdo.online` (BDO), `com.bpi.mobile` (BPI), `com.metrobank.mobilebanking` (Metrobank), `com.landbank.lbpemv` (Land Bank)
- E-wallets: `com.gcash.android` (GCash — dominant), `com.paymaya.android` (Maya)

### Amount Patterns
- `₱1,500.00`, `PHP 1500`, `P1,500.00`

### Sample SMS
```
GCash: PHP 500.00 sent to 09171234567 via GCash. Your new balance is PHP 1,500.00. Ref No: GC1234567890.

BDO: Your account XXXX1234 has been debited ₱5,000.00 on 10/31/2026. Available Balance: ₱25,000.00.

BPI: ₱2,000 credited to your account XXXX5678 on 10/31/2026. Balance: ₱15,000.00.
```

---

## Thailand (TH)

**Currency:** THB (฿ / THB), `th_TH` locale  
**Confidence:** Low-Medium

### Amount Patterns
- `฿1,500.00`, `THB 1,500`, `1,500.00 THB`

### Source Packages
- Default SMS app
- Bank apps: `th.co.scb.easymobileapp` (SCB), `com.kasikorn.retail.mbanking.wap` (KBank), `th.co.kiatnakin.mobilebanking` (KKP), `com.bbl.mobilebanking.android` (Bangkok Bank)
- PromptPay (similar to UPI/PIX)

### Sample SMS
```
SCB: Account XXXX1234 debited THB 2,000.00 on 31/10/2026. Available Balance: THB 25,000.00.

KBank: รับโอน ฿1,500 จาก สมชาย ใจดี เวลา 14:32. คงเหลือ ฿5,000.
```

---

## Vietnam (VN)

**Currency:** VND (₫ / VND), `vi_VN` locale  
**Important:** VND has 0 decimal places; large amounts  
**Confidence:** Low-Medium

### Amount Patterns
- `500.000đ`, `₫500,000`, `500000 VND`

### Source Packages
- Default SMS app
- Bank apps: `com.vietcombank.vcbmobile` (Vietcombank), `com.vietinbank.ipay` (VietinBank), `com.bidv.smartbanking` (BIDV), `com.agribank.agribankmobile` (Agribank)
- E-wallets: `vn.momo.client` (MoMo), `com.vnpay.app` (VNPay), `com.zalopay.wallet` (ZaloPay)

### Sample SMS
```
Vietcombank: TK XXXX1234 giam 500,000VND luc 31/10/2026 14:32. So du: 5,000,000VND. Ref: VCB123456.

MoMo: Ban da gui 100,000d den 0901234567. So du MoMo: 500,000d.
```

---

## Malaysia (MY)

**Currency:** MYR (RM), `ms_MY` locale  
**Confidence:** Medium

### Amount Patterns
- `RM1,500.00`, `MYR 1500`

### Source Packages
- Default SMS app
- Bank apps: `com.maybank2u.life` (Maybank), `com.rhbmobile.rhbbankberhad` (RHB), `com.cimbclicks.android` (CIMB), `com.publicmutual.mobileapp` (Public Bank), `com.hlb.mobile.banking` (Hong Leong Bank)
- E-wallets: `com.boost.merchant` (Boost), `com.tng.ewallet` (Touch 'n Go), `com.grab.grabpay.merchant` (GrabPay)

### Sample SMS
```
Maybank: RM 500.00 has been debited from your account XXXX1234 on 31/10/2026. Balance: RM 5,000.00. Call 1300 88 6688 if not you.

RHB: RM 1,500 credited to your account XXXX5678 on 31-Oct-26. Available Balance: RM 8,500.00.

Touch 'n Go: RM50.00 paid to MerchantName. Balance: RM200.00. Ref: TNG123456.
```

---

## Singapore (SG)

**Currency:** SGD (S$), `en_SG` locale  
**Confidence:** High (Clean English formats, high digital penetration, PayNow alerts)

### Notification Channels
- SMS: Sent for card transactions above threshold (usually S$100 or S$500 by default, customizable down to S$0.01) and PayNow transfers.
- In-App Push Notifications: DBS digibank, OCBC Digital, UOB TMRW send real-time push for every card transaction and transfer.

### Source Packages
- Default SMS apps: `com.google.android.apps.messaging`, `com.samsung.android.messaging`
- Bank apps:
  - DBS / POSB: `com.dbs.sg.dbsmbanking` (digibank SG), `com.dbs.sg.posbmbanking`
  - OCBC: `com.ocbc.mobile`
  - UOB: `com.uob.mcp.digital` (UOB TMRW SG)
  - Standard Chartered SG: `com.sc.bca`
  - Citibank SG: `com.citibank.mobile.sg`
  - GXS Bank: `com.gxs.bank`
  - Trust Bank: `sg.trustbank.trust`
  - GrabPay: `com.grabtaxi.passenger`

### Sender / Title Patterns
- Sender: `DBS`, `POSB`, `OCBC`, `UOB`, `SCBSG`, `CITISG`, `PAYNOW`
- Title: Transaction Alert, Card Debit Alert, PayNow Alert, DBS digibank, OCBC Digital

### Amount Patterns
- Prefix: `S$ 500.00`, `S$500.00`, `SGD 500.00`, `SGD500`
- Suffix: `500.00 SGD`, `500 SGD`
- Number format: Standard comma-thousands and dot-decimal (`1,234.56`)

### Wording & Keywords
- Debit: `debited`, `paid`, `spent`, `transferred`, `has been charged`, `payment of`, `PayNow to`, `sent`
- Credit: `credited`, `received`, `deposited`, `PayNow from`, `refund`, `cashback`
- Ignore: `OTP`, `verification code`, `failed`, `declined`, `due`, `statement available`

### Synthetic Samples
```
DBS: S$ 500.00 was debited from your account ending 1234 on 31/10/2026. Ref: 2026103112345. Available Balance: S$ 12,450.00.

OCBC: You made a PayNow transfer of S$75.00 to 91234567 on 31 Oct 2026 14:30. Available Bal: S$4,320.50.

UOB: S$ 1,250.00 has been credited to your account ending 5678 on 31/10/2026 via PayNow. Balance: S$ 8,900.00.
```

---

## Australia (AU)

**Currency:** AUD ($), `en_AU` locale  
**Confidence:** Medium-Low (Australian banks primarily use in-app push notifications; SMS less common)

### Amount Patterns
- `$1,500.00`, `AUD 1500`

### Source Packages
- Default SMS app
- Bank apps: `au.com.commbank.ebanking.android.v2` (CommBank), `com.anz.shield` (ANZ), `au.com.westpac.bank.mobile.android` (Westpac), `au.com.nab.mobile` (NAB)
- `com.up.banking` (Up Bank)

### Sample SMS
```
CommBank: A payment of $500.00 was made from your account XXXX1234 on 31 Oct 2026. Balance: $2,500.00.

ANZ: $1,000.00 was deposited into your account ending 5678 on 31/10/2026. Available Balance: $10,000.00.
```

---

## New Zealand (NZ)

**Currency:** NZD ($), `en_NZ` locale  
**Confidence:** Low

### Amount Patterns
- `$1,500.00`, `NZD 1500`

### Source Packages
- Default SMS app
- `com.anz.android` (ANZ NZ), `com.asb.banking.tablet` (ASB), `nz.co.bnz.bnzmobile` (BNZ), `nz.co.westpac` (Westpac NZ)

---

## Global Neo-banks & Wallets

Global and multi-national fintech platforms provide push notifications for transactions across many countries.

### 1. Revolut
- **Package:** `com.revolut.revolut`
- **Notification Type:** Real-time push notification for every card transaction, exchange, or transfer.
- **Formats:** Multi-currency (`€45.99 spent at Tesco`, `You spent $12.50 at Starbucks`, `You received £100.00 from John`).
- **Confidence:** High

### 2. Wise (formerly TransferWise)
- **Package:** `com.transferwise.android`
- **Notification Type:** Real-time push notification for money sent, converted, or received.
- **Formats:** `You sent $500.00 to John (ref: WISE123)`, `You received €250.00 from Acidity Ltd`.
- **Confidence:** High

### 3. Monzo
- **Package:** `co.monzo.android`
- **Notification Type:** Push for all purchases.
- **Formats:** `You spent £45.99 at Tesco`, `£1,500.00 deposited into your account`.
- **Confidence:** High

### 4. N26
- **Package:** `de.number26.android`
- **Notification Type:** Push notification for account movements across EU.
- **Formats:** European format (`1.234,56 EUR wurde abgebucht`, `50,00 € spent at Rewe`).
- **Confidence:** High

### 5. Nubank
- **Package:** `com.nu.production`
- **Notification Type:** Instant push for card and PIX payments in Brazil and Mexico.
- **Formats:** `Você fez um PIX de R$ 350,00 para Maria Silva`, `Compra de R$ 85,00 aprovada no cartão final 1234`.
- **Confidence:** High

### 6. GCash & Maya (Philippines)
- **Packages:** `com.globe.gcash.android`, `com.paymaya`
- **Notification Type:** SMS and push notification.
- **Formats:** `You have paid ₱500.00 of GCash to Merchant`, `You received ₱1,000.00 from Juan Cruz`.
- **Confidence:** High

### 7. bKash (Bangladesh)
- **Package:** `com.bkash.banking`
- **Notification Type:** SMS and in-app push.
- **Formats:** `You have received Tk 1,500.00 from 01712345678. Fee Tk 0.00. Balance Tk 5,420.00. TrxID 9A8B7C6D`.
- **Confidence:** High

### 8. GoPay & OVO (Indonesia)
- **Packages:** `com.gojek.app`, `ovo.id`
- **Notification Type:** Push notifications for QRIS payments, transfers, ride payments.
- **Formats:** `Kamu telah membayar Rp 50.000 ke Toko XYZ`, `Transfer Rp 200.000 berhasil ke Rekening BCA`.
- **Confidence:** High

### 9. STC Pay / Urpay (Saudi Arabia)
- **Packages:** `com.stc.stcpay`, `com.alrajhibank.urpay`
- **Notification Type:** Push notifications for wallet spends and transfers.
- **Formats:** `SAR 150.00 paid to Cafe via stc pay`, `SAR 500.00 received from Mohammed`.
- **Confidence:** High

---

## Summary: Special Parsing Considerations

| Region | Currency | Decimal Format | Zero Decimals | Notes |
|---|---|---|---|---|
| India | INR ₹ | `1,23,456.78` | No | Indian numbering system |
| Europe (DE/FR/ES) | EUR € | `1.234,56` | No | Dot=thousands, comma=decimal |
| Brazil | BRL R$ | `1.234,56` | No | Same as Europe |
| Turkey | TRY ₺ | `1.234,56` | No | Same as Europe |
| Indonesia | IDR Rp | `1.000.000` | Yes | Dot for thousands, no decimal |
| Japan | JPY ¥ | `1,000` | Yes | No decimal places |
| South Korea | KRW ₩ | `1,000` | Yes | No decimal places |
| Vietnam | VND ₫ | `500,000` | Yes | No decimal places |
| Kuwait/Bahrain/Oman | KWD/BHD/OMR | `1,000.000` | No (3 places!) | 3 decimal places |
| All others | Standard | `1,234.56` | Varies | US/UK standard |
