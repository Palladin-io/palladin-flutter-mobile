package io.palladin.mobile.sharing;

import java.util.HashMap;
import java.util.Map;
import java.util.function.LongSupplier;
import java.util.regex.Pattern;

/** A single process-memory slot; no Intent, saved-state or persistence API. */
public final class EntryShareMailbox {
    public static final long MAX_AGE_MS = 15 * 60 * 1000;
    private static final String SHARE_PATH =
        "/share/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}";
    private static final String FRAGMENT =
        "#v=1&key=[A-Za-z0-9_-]{43}&access=[A-Za-z0-9_-]{43}";
    private final LongSupplier wallClock;
    private final LongSupplier monotonicClock;
    private String pending;
    private long receivedAt, receivedElapsed, generation;

    public EntryShareMailbox(LongSupplier wallClock, LongSupplier monotonicClock) {
        this.wallClock = wallClock;
        this.monotonicClock = monotonicClock;
    }

    public synchronized long offer(String candidate, String expectedOrigin) {
        clear();
        if (candidate == null || candidate.length() > 2048 || expectedOrigin == null ||
            !expectedOrigin.matches("https://[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?")) {
            return generation;
        }
        if (!candidate.matches(Pattern.quote(expectedOrigin) + SHARE_PATH + FRAGMENT)) {
            return generation;
        }
        pending = candidate;
        receivedAt = wallClock.getAsLong();
        receivedElapsed = monotonicClock.getAsLong();
        return generation;
    }

    public synchronized Map<String, Object> take() {
        Map<String, Object> result = new HashMap<>();
        result.put("generation", generation);
        if (pending != null && !expired()) {
            result.put("url", pending);
            result.put("receivedAtUnixMs", receivedAt);
            result.put("ageMilliseconds", monotonicClock.getAsLong() - receivedElapsed);
        }
        pending = null;
        return result;
    }

    public synchronized long clear() {
        pending = null;
        receivedAt = 0;
        receivedElapsed = 0;
        return ++generation;
    }

    private boolean expired() {
        long age = monotonicClock.getAsLong() - receivedElapsed;
        return age < 0 || age >= MAX_AGE_MS ||
            wallClock.getAsLong() - receivedAt >= MAX_AGE_MS;
    }
}
