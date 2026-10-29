package io.palladin.mobile.autofill

import org.junit.Assert.*
import org.junit.Test

class CredentialAssetLinksTest {
    private val signer = List(32) { "AB" }.joinToString(":")
    private fun statement(relation: String = "delegate_permission/common.get_login_creds", packageName: String = "example.app", cert: String = signer) =
        """[{"relation":["$relation"],"target":{"namespace":"android_app","package_name":"$packageName","sha256_cert_fingerprints":["$cert"]}}]"""

    @Test fun executesActualPlatformStreamingReader() {
        android.util.JsonReader(java.io.StringReader("[]")).use { reader ->
            reader.beginArray(); reader.endArray()
            assertEquals(android.util.JsonToken.END_DOCUMENT, reader.peek())
        }
    }

    @Test fun exactPackageAndAllCurrentSignersNeedExplicitCredentialRelation() {
        assertTrue(CredentialAssetLinks.authorizes(statement(), "example.app", setOf(signer)))
        assertFalse(CredentialAssetLinks.authorizes(statement("delegate_permission/common.handle_all_urls"), "example.app", setOf(signer)))
        assertFalse(CredentialAssetLinks.authorizes(statement(), "other.app", setOf(signer)))
        assertFalse(CredentialAssetLinks.authorizes(statement(), "example.app", setOf(signer, "CD:".repeat(31) + "CD")))
        assertFalse(CredentialAssetLinks.authorizes(statement(), "example.app", emptySet()))
        val second = "CD:".repeat(31) + "CD"
        val both = statement().replace("[\"$signer\"]", "[\"$signer\",\"$second\"]")
        assertTrue(CredentialAssetLinks.authorizes(both, "example.app", setOf(signer, second)))
        assertFalse(CredentialAssetLinks.authorizes(statement(cert = second), "example.app", setOf(signer)))
        assertFalse(CredentialAssetLinks.authorizes(statement("common.get_login_creds"), "example.app", setOf(signer)))
    }

    @Test fun unrelatedJsonMetadataAndStandaloneIncludesSupplyNoAuthority() {
        val extension = statement().replace("{\"relation\"", "{\"relation_extensions\":{\"metadata\":{\"exclude\":true,\"priority\":1,\"optional\":null}},\"relation\"")
        assertTrue(CredentialAssetLinks.authorizes(extension, "example.app", setOf(signer)))
        val include = """{"include":"https://other.invalid/statements.json"}"""
        assertFalse(CredentialAssetLinks.authorizes("[$include]", "example.app", setOf(signer)))
        assertTrue(CredentialAssetLinks.authorizes("[$include," + statement().drop(1), "example.app", setOf(signer)))
        for (bad in listOf(statement().replace("\"android_app\"", "true"),
            statement().replace("[\"$signer\"]", "[null]"),
            statement().replace("[\"delegate_permission/common.get_login_creds\"]", "[1]"))) {
            assertFalse(CredentialAssetLinks.authorizes(bad, "example.app", setOf(signer)))
            assertFalse(CredentialAssetLinks.authorizes(statement().dropLast(1) + "," + bad.drop(1), "example.app", setOf(signer)))
        }
    }

    @Test fun strictStreamingReaderRejectsLenientDuplicatesIncludesAndTrailingData() {
        val valid = statement()
        for (bad in listOf(
            valid + "[]", valid.replace("\"relation\":", "\"relation\":[],\"relation\":"),
            valid.replace("\"namespace\":", "\"namespace\":\"web\",\"namespace\":"),
            valid.replace("{\"relation\"", "{\"include\":\"https://other.invalid\",\"relation\""),
            valid.replace("\"relation\"", "relation"), valid.replace("\"android_app\"", "'android_app'"),
            valid.replace("[{", "[/*comment*/{"), valid.dropLast(1), " ".repeat(65537),
        )) assertFalse(CredentialAssetLinks.authorizes(bad, "example.app", setOf(signer)))
    }
}
