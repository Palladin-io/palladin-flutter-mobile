package io.palladin.autofill.form

internal fun fixtureContent(url: String, html: String): String? =
    html.takeIf { url == "https://fixture.invalid/" }
