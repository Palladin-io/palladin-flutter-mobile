package io.palladin.mobile.sharing;

import org.junit.Test;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;
import static org.junit.Assert.*;

public class EntryShareMailboxTest {
    private static final String ORIGIN = "https://sharing.example.test";
    private static final String LINK = ORIGIN +
        "/share/00112233-4455-4677-8899-aabbccddeeff#v=1&key=" +
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAE&access=" +
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAI";
    private final AtomicLong wall = new AtomicLong(1_790_000_000_000L);
    private final AtomicLong elapsed = new AtomicLong(1000);
    private final EntryShareMailbox mailbox = new EntryShareMailbox(wall::get, elapsed::get);

    @Test public void transfersOnceWithOriginalWallTimeAndMonotonicAge() {
        long received = wall.get();
        long generation = mailbox.offer(LINK, ORIGIN);
        elapsed.addAndGet(4500);
        Map<String, Object> result = mailbox.take();
        assertEquals(generation, result.get("generation"));
        assertEquals(LINK, result.get("url"));
        assertEquals(received, result.get("receivedAtUnixMs"));
        assertEquals(4500L, result.get("ageMilliseconds"));
        assertEquals(generation, mailbox.take().get("generation"));
        assertFalse(mailbox.take().containsKey("url"));
    }

    @Test public void rejectsAliasesWrongOriginsMalformedAndOversizeLinks() {
        String[] rejected = {
            LINK.replace("https:", "http:"),
            LINK.replace(ORIGIN, ORIGIN + ".evil.test"),
            LINK.replace(ORIGIN, "https://user@sharing.example.test"),
            LINK.replace(ORIGIN, ORIGIN + ":443"),
            LINK.replace("/share/", "/elsewhere/../share/"),
            LINK.replace("/share/0", "/share/%30"),
            LINK.replace("#", "?x=1#"),
            LINK + "&extra=secret", LINK + "\n", LINK + " ", null,
            LINK + new String(new char[2048]).replace('\0', 'x'),
        };
        for (String value : rejected) {
            mailbox.offer(LINK, ORIGIN);
            long generation = mailbox.offer(value, ORIGIN);
            Map<String, Object> result = mailbox.take();
            assertEquals(generation, result.get("generation"));
            assertFalse(result.containsKey("url"));
        }
    }

    @Test public void nativeClockRollbackCannotExtendMonotonicExpiry() {
        mailbox.offer(LINK, ORIGIN);
        wall.addAndGet(-3_600_000);
        elapsed.addAndGet(EntryShareMailbox.MAX_AGE_MS);
        assertFalse(mailbox.take().containsKey("url"));
    }

    @Test public void wallExpiryWinsEvenWhenMonotonicTimeHasNotAdvanced() {
        mailbox.offer(LINK, ORIGIN);
        wall.addAndGet(EntryShareMailbox.MAX_AGE_MS);
        assertFalse(mailbox.take().containsKey("url"));
    }

    @Test public void unexpectedMonotonicRollbackFailsClosed() {
        mailbox.offer(LINK, ORIGIN);
        elapsed.decrementAndGet();
        assertFalse(mailbox.take().containsKey("url"));
    }

    @Test public void replacementAndClearInvalidateOlderGeneration() {
        long old = mailbox.offer(LINK, ORIGIN);
        String replacement = LINK.replace("ddeeff", "ddeeaa");
        long fresh = mailbox.offer(replacement, ORIGIN);
        assertTrue(fresh > old);
        assertEquals(replacement, mailbox.take().get("url"));
        mailbox.offer(LINK, ORIGIN);
        assertTrue(mailbox.clear() > fresh);
        assertFalse(mailbox.take().containsKey("url"));
    }

    @Test public void malformedBuildOriginDoesNotAuthorizeAnyCandidate() {
        for (String origin : new String[] {null, "", "http://sharing.example.test", ORIGIN + "/", ORIGIN + "?", "https://*.example.test"}) {
            mailbox.offer(LINK, origin);
            assertFalse(mailbox.take().containsKey("url"));
        }
    }

    @Test public void emptyMailboxContainsNoCapabilityOrTimingMetadata() {
        assertEquals(1, mailbox.take().size());
        assertEquals(0L, mailbox.take().get("generation"));
    }
}
