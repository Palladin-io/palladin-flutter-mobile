package io.palladin.mobile.autofill

import okhttp3.Call
import okhttp3.CookieJar
import okhttp3.Authenticator
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import java.net.InetAddress
import java.net.Proxy
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.concurrent.TimeUnit

internal class CredentialAssociationNetwork(
    private val resolve: (String) -> List<InetAddress> = { InetAddress.getAllByName(it).toList() },
    private val newCall: (OkHttpClient, Request) -> Call = { client, request -> client.newCall(request) },
) {
    fun fetch(key: CredentialAssociationKey, register: (Call) -> Boolean): Boolean {
        // Feed precisely these checked addresses to the actual connector. There is
        // no second DNS resolution between the public-address check and TLS.
        val addresses = resolve(key.host)
        if (addresses.isEmpty() || addresses.size > 16 || addresses.any { !isPublicAddress(it) }) return false
        val client = OkHttpClient.Builder()
            .dns { requested -> require(requested == key.host); addresses }
            .proxy(Proxy.NO_PROXY).cookieJar(CookieJar.NO_COOKIES)
            .authenticator(Authenticator.NONE).proxyAuthenticator(Authenticator.NONE)
            .cache(null).followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false)
            .protocols(listOf(Protocol.HTTP_1_1))
            .callTimeout(3, TimeUnit.SECONDS).connectTimeout(1, TimeUnit.SECONDS).readTimeout(1500, TimeUnit.MILLISECONDS)
            .build()
        val request = Request.Builder().url("https://${key.host}/.well-known/assetlinks.json")
            .header("Accept", "application/json").header("Accept-Encoding", "identity")
            .header("Connection", "close").build()
        val call = newCall(client, request)
        if (!register(call)) { call.cancel(); return false }
        return try {
            call.execute().use { response ->
                if (response.code != 200 || response.request.url != request.url ||
                    response.header("Content-Type")?.substringBefore(';')?.trim()?.lowercase() != "application/json" ||
                    response.header("Content-Encoding")?.let { !it.equals("identity", true) } == true) return false
                val body = response.body
                if (body.contentLength() > CredentialAssetLinks.MAX_BYTES) return false
                val source = body.source()
                if (source.request(CredentialAssetLinks.MAX_BYTES + 1L)) return false
                val bytes = source.readByteArray()
                val json = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
                CredentialAssetLinks.authorizes(json, key.packageName, key.signers)
            }
        } finally {
            client.connectionPool.evictAll()
        }
    }

    companion object {
        fun isPublicAddress(address: InetAddress): Boolean {
            val b = address.address.map { it.toInt() and 255 }
            if (b.size == 4) {
                if (b[0] == 0 || b[0] == 10 || b[0] == 127 || b[0] >= 224) return false
                if (b[0] == 100 && b[1] in 64..127 || b[0] == 169 && b[1] == 254 ||
                    b[0] == 172 && b[1] in 16..31 || b[0] == 192 && b[1] == 168 ||
                    b[0] == 192 && b[1] == 0 || b[0] == 192 && b[1] == 88 && b[2] == 99 ||
                    b[0] == 198 && b[1] in 18..19 || b[0] == 198 && b[1] == 51 && b[2] == 100 ||
                    b[0] == 203 && b[1] == 0 && b[2] == 113) return false
                return true
            }
            if (b.size != 16 || b[0] and 0xe0 != 0x20) return false
            // Deny IPv6 special-purpose, documentation and transition networks.
            if (b[0] == 0x20 && b[1] == 0x01 && (b[2] < 2 || b[2] == 0x0d && b[3] == 0xb8)) return false
            if (b[0] == 0x20 && b[1] == 0x02 || b[0] == 0x3f && b[1] == 0xff) return false
            return true
        }
    }
}
