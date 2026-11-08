# Quiz — AWS Backup & Restore

Test yourself. Answers are hidden — click to reveal.

---

### 1. What is the main advantage of AWS Backup over taking snapshots manually per service?

A. It is free for all resource types
B. One central plan, schedule, retention, and lifecycle policy across EC2, RDS, DynamoDB, EFS, FSx, and S3
C. It backs up data faster than native snapshots
D. It replaces the need for Multi-AZ deployments

<details>
<summary>Answer</summary>

**B.** AWS Backup is a single control plane: one plan covers many resource types with consistent scheduling, retention, and lifecycle rules — instead of a different snapshot script per service.

</details>

---

### 2. An attacker gains admin access to your AWS account and deletes all EBS snapshots and backup vaults. Which combination would have saved your data?

A. Daily snapshots with 30-day retention
B. Cross-region copy + Vault Lock in Compliance mode, with a copy in an isolated account
C. Enabling S3 versioning on the backup bucket
D. MFA on the root account

<details>
<summary>Answer</summary>

**B.** Vault Lock (Compliance mode) makes recovery points immutable — even root can't delete them before expiry — and a cross-account copy lives outside the compromised account. Retention alone (A) doesn't help if the attacker can delete the backups.

</details>

---

### 3. Your RDS database is accidentally wiped at 14:00. The last daily snapshot was taken at 02:00. What is the best recovery option, and what does it imply about RPO?

A. Restore the 02:00 snapshot — you lose 12 hours of data, so your RPO is 24 h
B. Restore the snapshot and replay binlogs — impossible with AWS Backup
C. Use point-in-time recovery (PITR) to restore to 13:59, if continuous backup was enabled — RPO near zero
D. Wait for the next scheduled backup

<details>
<summary>Answer</summary>

**C.** With continuous backup / PITR enabled on RDS, you can restore to any second in the retention window — so the data loss is minutes, not 12 hours. This is why PITR matters on top of daily snapshots.

</details>

---

### 4. Why should backup lifecycle rules move recovery points to cold storage instead of keeping everything in warm storage?

A. Cold storage is faster to restore from
B. Cold storage costs roughly 75% less, and old recovery points are rarely restored
C. Warm storage has a 30-day maximum retention
D. Cold storage is required for Vault Lock

<details>
<summary>Answer</summary>

**B.** Cold storage is far cheaper; recovery points older than a week are almost never restored urgently, so tiering them down saves most of the backup bill with no practical downside.

</details>

---

### 5. Your team has never tested a restore. The backup jobs all report COMPLETED. What is the biggest risk?

A. The backups are probably fine — COMPLETED means the data is verified
B. The restore might fail (corrupt snapshot, missing permissions, wrong region) and you'll only discover it during a real incident
C. The backup plan will stop working after 30 days
D. Vault Lock will block all future restores

<details>
<summary>Answer</summary>

**B.** COMPLETED only means the backup job finished — it says nothing about whether a restore works. Untested backups are the most common DR failure. Schedule monthly restore drills and measure real RTO/RPO.

</details>

---

**Score yourself:** 5/5 — you're ready to own the backup strategy. 3–4 — re-read the Vault Lock and restore-testing sections. 0–2 — start with the README, then come back.
