// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

package com.atc.palmaccess

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.ByteBuffer
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Cryptography for the app. Keys that protect data at rest live in the Android Keystore
 * (hardware-backed where available) and can never be exported from the device.
 *
 *  - Palm templates: AES-256-GCM with a Keystore key.
 *  - Admin PIN: PBKDF2-HMAC-SHA256 over HMAC(Keystore pepper, PIN). A copied database is
 *    useless for offline PIN brute force because the pepper never leaves the Keystore.
 *  - Backups: AES-256-GCM with a key derived from the admin-chosen backup password.
 */
object SecureVault {
    private const val KEYSTORE = "AndroidKeyStore"
    private const val TEMPLATE_KEY = "atc_template_key_v1"
    private const val PEPPER_KEY = "atc_pin_pepper_v1"
    private const val PIN_ITERATIONS = 120_000
    private const val BACKUP_ITERATIONS = 210_000
    private const val BACKUP_AAD = "atc-palm-backup-v1"
    private val random = SecureRandom()

    private fun keyStore() = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun templateKey(): SecretKey {
        val ks = keyStore()
        (ks.getKey(TEMPLATE_KEY, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        gen.init(
            KeyGenParameterSpec.Builder(TEMPLATE_KEY, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return gen.generateKey()
    }

    private fun pepperKey(): SecretKey {
        val ks = keyStore()
        (ks.getKey(PEPPER_KEY, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, KEYSTORE)
        gen.init(KeyGenParameterSpec.Builder(PEPPER_KEY, KeyProperties.PURPOSE_SIGN).build())
        return gen.generateKey()
    }

    private fun b64(b: ByteArray) = Base64.encodeToString(b, Base64.NO_WRAP)
    private fun unb64(s: String) = Base64.decode(s, Base64.NO_WRAP)

    // ------------------------------------------------------------ templates

    fun encrypt(plain: String): String {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, templateKey())
        val ct = c.doFinal(plain.toByteArray(Charsets.UTF_8))
        return "v1:" + b64(c.iv) + ":" + b64(ct)
    }

    fun decrypt(token: String): String {
        val parts = token.split(":")
        require(parts.size == 3 && parts[0] == "v1") { "Unsupported ciphertext" }
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, templateKey(), GCMParameterSpec(128, unb64(parts[1])))
        return String(c.doFinal(unb64(parts[2])), Charsets.UTF_8)
    }

    // ------------------------------------------------------------ PIN

    private fun pepper(secret: String): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(pepperKey())
        return mac.doFinal(secret.toByteArray(Charsets.UTF_8))
    }

    /** Returns "pbkdf2$iterations$salt$hash". */
    fun hashPin(pin: String): String {
        val salt = ByteArray(16).also { random.nextBytes(it) }
        val hash = pbkdf2(pepper(pin), salt, PIN_ITERATIONS, 32)
        return "pbkdf2$$PIN_ITERATIONS$${b64(salt)}$${b64(hash)}"
    }

    fun verifyPin(pin: String, stored: String): Boolean {
        val p = stored.split("$")
        if (p.size != 4 || p[0] != "pbkdf2") return false
        val expected = unb64(p[3])
        val actual = pbkdf2(pepper(pin), unb64(p[2]), p[1].toInt(), expected.size)
        return MessageDigest.isEqual(expected, actual) // constant-time
    }

    // ------------------------------------------------------------ backups

    fun encryptBackup(plain: String, password: String): String {
        val salt = ByteArray(16).also { random.nextBytes(it) }
        val iv = ByteArray(12).also { random.nextBytes(it) }
        val key = SecretKeySpec(pbkdf2(password.toByteArray(Charsets.UTF_8), salt, BACKUP_ITERATIONS, 32), "AES")
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, iv))
        c.updateAAD(BACKUP_AAD.toByteArray())
        val ct = c.doFinal(plain.toByteArray(Charsets.UTF_8))
        return """{"format":"atc-palm-backup","version":1,"kdf":"pbkdf2-sha256","iterations":$BACKUP_ITERATIONS,""" +
            """"salt":"${b64(salt)}","iv":"${b64(iv)}","data":"${b64(ct)}"}"""
    }

    fun decryptBackup(salt: String, iv: String, data: String, iterations: Int, password: String): String {
        require(iterations in 100_000..5_000_000) { "Invalid backup parameters" }
        val key = SecretKeySpec(pbkdf2(password.toByteArray(Charsets.UTF_8), unb64(salt), iterations, 32), "AES")
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, unb64(iv)))
        c.updateAAD(BACKUP_AAD.toByteArray())
        return String(c.doFinal(unb64(data)), Charsets.UTF_8)
    }

    // ------------------------------------------------------------ PBKDF2-HMAC-SHA256 (RFC 8018)
    // Implemented directly because SecretKeyFactory "PBKDF2WithHmacSHA256" needs API 26+.

    private fun pbkdf2(password: ByteArray, salt: ByteArray, iterations: Int, length: Int): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(if (password.isEmpty()) ByteArray(1) else password, "HmacSHA256"))
        val hLen = mac.macLength
        val blocks = (length + hLen - 1) / hLen
        val out = ByteArray(blocks * hLen)
        for (i in 1..blocks) {
            mac.update(salt)
            mac.update(ByteBuffer.allocate(4).putInt(i).array())
            var u = mac.doFinal()
            val t = u.copyOf()
            for (j in 1 until iterations) {
                u = mac.doFinal(u)
                for (k in t.indices) t[k] = (t[k].toInt() xor u[k].toInt()).toByte()
            }
            System.arraycopy(t, 0, out, (i - 1) * hLen, hLen)
        }
        return out.copyOf(length)
    }

    fun randomToken(bytes: Int = 32): String = b64(ByteArray(bytes).also { random.nextBytes(it) })

    fun hmacSha256Hex(key: String, message: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        return mac.doFinal(message.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }
}
