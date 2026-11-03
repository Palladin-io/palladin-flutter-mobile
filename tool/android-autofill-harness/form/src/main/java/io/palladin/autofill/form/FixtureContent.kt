package io.palladin.autofill.form

internal fun fixtureContent(url: String, html: String, dalFixture: Boolean = false): String? =
    html.takeIf { url == (if (dalFixture) "https://example.com/" else "https://fixture.invalid/") }
