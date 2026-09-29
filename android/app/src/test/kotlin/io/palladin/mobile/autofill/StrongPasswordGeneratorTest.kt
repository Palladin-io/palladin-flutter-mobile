package io.palladin.mobile.autofill

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StrongPasswordGeneratorTest {
    @Test
    fun generatesTwentyCharactersFromEveryRequiredClass() {
        repeat(100) {
            val password = StrongPasswordGenerator.generate()
            assertEquals(20, password.length)
            assertTrue(password.any(Char::isLowerCase))
            assertTrue(password.any(Char::isUpperCase))
            assertTrue(password.any(Char::isDigit))
            assertTrue(password.any { it in "!@#$%^&*()-_=+[]{};:,.?/" })
        }
    }

    @Test
    fun successivePasswordsDiffer() {
        assertNotEquals(StrongPasswordGenerator.generate(), StrongPasswordGenerator.generate())
    }
}
