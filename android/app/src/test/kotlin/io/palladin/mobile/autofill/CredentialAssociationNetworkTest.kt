package io.palladin.mobile.autofill

import java.net.InetAddress
import okhttp3.Call
import okhttp3.Response
import okhttp3.Protocol
import okhttp3.ResponseBody.Companion.toResponseBody
import org.mockito.Mockito.verify
import org.mockito.Mockito.never
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`
import org.junit.Assert.*
import org.junit.Test

class CredentialAssociationNetworkTest {
    @Test fun boundedResponseRequiresJson200WithoutRedirectOrCompression() {
        val signer = List(32) { "AB" }.joinToString(":")
        val key = CredentialAssociationKey("example.com", "example.app", setOf(signer))
        val json = """[{"relation":["delegate_permission/common.get_login_creds"],"target":{"namespace":"android_app","package_name":"example.app","sha256_cert_fingerprints":["$signer"]}}]"""
        fun fetch(code: Int = 200, mime: String = "application/json", encoding: String = "identity", body: String = json): Boolean {
            val transport = CredentialAssociationNetwork({ listOf(InetAddress.getByName("8.8.8.8")) }, { client, request ->
                assertFalse(client.followRedirects); assertFalse(client.followSslRedirects)
                assertFalse(client.retryOnConnectionFailure)
                assertEquals(java.net.Proxy.NO_PROXY, client.proxy)
                assertEquals(okhttp3.CookieJar.NO_COOKIES, client.cookieJar)
                assertEquals("https://example.com/.well-known/assetlinks.json", request.url.toString())
                assertNull(request.header("Authorization")); assertNull(request.header("Cookie"))
                assertEquals("identity", request.header("Accept-Encoding"))
                val call = mock(Call::class.java)
                `when`(call.execute()).thenReturn(Response.Builder().request(request).protocol(Protocol.HTTP_1_1)
                    .code(code).message("synthetic").header("Content-Type", mime).header("Content-Encoding", encoding)
                    .body(body.toResponseBody()).build())
                call
            })
            return transport.fetch(key) { true }
        }
        assertTrue(fetch())
        assertFalse(fetch(code = 302)); assertFalse(fetch(code = 404))
        assertFalse(fetch(mime = "text/html")); assertFalse(fetch(encoding = "gzip"))
        assertFalse(fetch(body = " ".repeat(65537))); assertFalse(fetch(body = json.dropLast(1)))
    }

    @Test fun connectorUsesOnlyCheckedDnsAndCanceledCallNeverExecutes() {
        var resolutions = 0
        val address = InetAddress.getByName("8.8.8.8")
        val call = mock(Call::class.java)
        val transport = CredentialAssociationNetwork({ resolutions++; listOf(address) }, { client, _ ->
            assertEquals(listOf(address), client.dns.lookup("example.com"))
            assertEquals(listOf(address), client.dns.lookup("example.com"))
            assertTrue(runCatching { client.dns.lookup("other.example.com") }.isFailure)
            call
        })
        assertFalse(transport.fetch(CredentialAssociationKey("example.com", "example.app", setOf("signer"))) { false })
        assertEquals(1, resolutions)
        verify(call).cancel()
        verify(call, never()).execute()
    }

    @Test fun malformedUtf8AndUnknownLengthOversizeCannotSupplyProof() {
        val key = CredentialAssociationKey("example.com", "example.app", setOf(List(32) { "AB" }.joinToString(":")))
        for (bytes in listOf(byteArrayOf(0xc3.toByte(), 0x28), ByteArray(65537) { 32 })) {
            val transport = CredentialAssociationNetwork({ listOf(InetAddress.getByName("8.8.8.8")) }, { _, request ->
                val body = object : okhttp3.ResponseBody() {
                    override fun contentType(): okhttp3.MediaType? = null
                    override fun contentLength() = -1L
                    override fun source(): okio.BufferedSource = okio.Buffer().write(bytes)
                }
                mock(Call::class.java).also { call ->
                    `when`(call.execute()).thenReturn(Response.Builder().request(request).protocol(Protocol.HTTP_1_1)
                        .code(200).message("synthetic").header("Content-Type", "application/json").body(body).build())
                }
            })
            assertFalse(runCatching { transport.fetch(key) { true } }.getOrDefault(false))
        }
    }

    @Test fun rejectsMixedDnsBeforeCreatingAnyHttpCall() {
        var calls = 0
        val transport = CredentialAssociationNetwork({ listOf(InetAddress.getByName("8.8.8.8"), InetAddress.getByName("127.0.0.1")) },
            { _, _ -> calls++; error("Must reject before connecting") })
        assertFalse(transport.fetch(CredentialAssociationKey("example.com", "example.app", setOf("signer"))) { true })
        assertEquals(0, calls)
    }

    @Test fun actualConnectionAddressesMustBeGloballyRoutable() {
        for (address in listOf("8.8.8.8", "1.1.1.1", "2606:4700:4700::1111"))
            assertTrue(address, CredentialAssociationNetwork.isPublicAddress(InetAddress.getByName(address)))
        for (address in listOf("0.0.0.0", "10.1.2.3", "100.64.0.1", "127.0.0.1", "169.254.169.254",
            "172.16.0.1", "192.168.1.1", "192.0.2.1", "198.18.0.1", "198.51.100.1", "203.0.113.1",
            "224.0.0.1", "255.255.255.255", "::", "::1", "fc00::1", "fe80::1", "ff02::1",
            "::ffff:127.0.0.1", "64:ff9b::7f00:1", "2001:db8::1", "2002:7f00:1::", "3fff::1"))
            assertFalse(address, CredentialAssociationNetwork.isPublicAddress(InetAddress.getByName(address)))
    }
}
