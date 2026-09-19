# Privacy Policy for Buddy: Auto Expense Tracker

**Last updated:** September 19, 2026

Thank you for choosing **Buddy: Auto Expense Tracker** ("we", "our", or "us"). We are committed to protecting your privacy and personal data. This Privacy Policy explains how our application collects, uses, and safeguards your information when you use our mobile application.

---

## 1. Information We Collect

### A. Notification & Transaction Data (Core Feature)
To automatically record your expenses without requiring manual input, Buddy uses Android's **Notification Listener Service** (`BIND_NOTIFICATION_LISTENER_SERVICE`).
- **What is processed:** The app inspects transactional notification alerts from banking apps, SMS alerts, and UPI payment apps (e.g., Google Pay, PhonePe, Paytm, CRED, HDFC, SBI, ICICI, etc.).
- **What is extracted:** Only the transaction amount, merchant/payee name, date/time, and transaction type (debit/credit).
- **What is strictly ignored:** We do NOT read, store, or process personal messages, chats, one-time passwords (OTPs), verification codes, security PINs, or bank account passwords. All notification filtering happens locally on your device.

### B. User Account Information
- When you register or log in using Google Sign-In or Email/Password, we collect your email address and display name via **Firebase Authentication** to identify your account and secure your data.

### C. Financial & Spending Records
- Categories, transaction notes, budget limits, and expense amounts you log (either automatically or manually) are stored securely in **Google Cloud Firestore** under your private authenticated user profile.

---

## 2. How We Use Your Information

We use the collected information solely to:
- Automatically log and categorize your daily expenses.
- Provide budget tracking, spending summaries, and visual analytics (charts and graphs).
- Sync your expense data across your devices when signed in.
- Enable user support and respond to bug reports or feature requests sent to `faysarukattil@gmail.com`.

**We do NOT sell, rent, trade, or monetize your personal or financial information to third parties or advertisers under any circumstances.**

---

## 3. Data Storage & Security

- **Encryption in Transit:** All communications between the app and our cloud backend (Firebase) are encrypted using industry-standard Transport Layer Security (TLS/HTTPS).
- **Access Control:** User data stored in Cloud Firestore is strictly isolated using Firestore Security Rules. Only your authenticated user account can access or modify your financial logs.
- **No Banking Credentials:** Buddy never requests, stores, or accesses your bank account login credentials, debit/credit card numbers, or UPI PINs.

---

## 4. User Control and Data Deletion

You have full control over your data:
- **Account & Data Deletion:** You can permanently delete your account and all associated transaction records, categories, and profile data at any time directly within the app:
  > **Settings** → **Account** → **Delete Account**
- When requested, all your records stored in Cloud Firestore and Firebase Authentication are permanently purged immediately.
- **Revoking Permissions:** You can disable notification access at any time through your Android device settings (**Settings** → **Apps** → **Special app access** → **Notification access** → **Buddy**).

---

## 5. Third-Party Services

Buddy uses trusted Google Firebase services to provide cloud infrastructure:
- **Firebase Authentication** (Identity management)
- **Cloud Firestore** (Encrypted cloud database)

Google's privacy policy regarding these services can be reviewed at: [https://policies.google.com/privacy](https://policies.google.com/privacy).

---

## 6. Children's Privacy

Buddy is not directed to children under the age of 13. We do not knowingly collect personal information from children under 13.

---

## 7. Changes to This Privacy Policy

We may update this Privacy Policy from time to time. Any changes will be posted on this page with an updated revision date.

---

## 8. Contact Us

If you have any questions, concerns, or requests regarding this Privacy Policy or your data, please contact us at:

- **Developer:** Faysal Arukattil
- **Email:** [faysarukattil@gmail.com](mailto:faysarukattil@gmail.com)
