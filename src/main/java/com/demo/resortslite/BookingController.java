package com.demo.resortslite;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.*;
// FIX cz-java-0069 (Lines 34-35): Replaced javax.servlet.http.HttpSession with Spring Session
// SessionRepository backed by Amazon ElastiCache for Redis. Sessions are now stored
// externally in Redis, enabling stateless horizontal scaling across EKS pods.
import org.springframework.session.Session;
import org.springframework.session.SessionRepository;
// FIX cz-java-0070 (Line 19): Replaced local in-memory HashMap cache with Spring Data Redis
// RedisTemplate backed by Amazon ElastiCache for Redis. Cache entries are now stored
// externally and shared across all EKS pod replicas, enabling effective horizontal scaling.
import org.springframework.data.redis.core.RedisTemplate;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/bookings")
public class BookingController {

    @Autowired
    private BookingService bookingService;

    // FIX cz-java-0069: Inject Spring Session SessionRepository (backed by Redis via
    // spring-session-data-redis) to replace in-memory HttpSession.
    // Sessions are stored in Amazon ElastiCache for Redis and shared across all EKS pods.
    @Autowired
    private SessionRepository<? extends Session> sessionRepository;

    // FIX cz-java-0070 (Line 19): Replaced local in-memory HashMap bookingCache with
    // RedisTemplate backed by Amazon ElastiCache for Redis (injected via EKS ConfigMap/Secret).
    // Before: private static final Map<String, Object> bookingCache = new HashMap<>();
    // After:  Redis-backed RedisTemplate<String, Object> shared across all EKS pod replicas.
    // Cache entries are visible to every pod instance, supporting horizontal scaling without
    // data loss on pod restart or scale-out events.
    @Autowired
    private RedisTemplate<String, Object> redisTemplate;

    // FIX cz-java-0057: Injected via environment variable REPORT_BASE_PATH (ConfigMap/EKS)
    @Value("${app.report.base-path:#{systemEnvironment['REPORT_BASE_PATH'] ?: '/var/reports'}}")
    private String reportBasePath;

    @PostMapping("/create")
    public Map<String, Object> createBooking(
            @RequestParam String guestName,
            @RequestParam String roomType,
            @RequestParam String checkIn,
            @RequestParam String checkOut,
            // FIX cz-java-0069 (Lines 34-35): Replaced HttpSession parameter with
            // @RequestHeader session ID resolved via Spring Session / Redis.
            // Session state is now stored in Amazon ElastiCache (Redis) and shared
            // across all EKS pod replicas, eliminating sticky-session requirements.
            @RequestHeader(value = "X-Auth-Token", required = false) String sessionId) {

        Map<String, Object> booking = bookingService.createBooking(guestName, roomType, checkIn, checkOut);

        // FIX cz-java-0069 (Lines 34-35): Store session attributes in Redis-backed Spring Session
        // instead of in-memory HttpSession. Session is identified by X-Auth-Token header
        // and persisted to Amazon ElastiCache, visible to all EKS pod instances.
        // Before: session.setAttribute("lastBooking", booking);  [HttpSession - in-memory, lost on restart]
        // Before: session.setAttribute("guestName", guestName);  [HttpSession - in-memory, lost on restart]
        // After:  Redis-backed SessionRepository.save(session)   [Externalized to ElastiCache]
        Session session = (sessionId != null) ? sessionRepository.findById(sessionId) : null;
        if (session == null) {
            session = sessionRepository.createSession();
        }
        session.setAttribute("lastBooking", booking);
        session.setAttribute("guestName", guestName);
        saveSession(session);

        // FIX cz-java-0070 (Line 19): Store booking in Amazon ElastiCache via RedisTemplate
        // instead of local in-memory HashMap. All EKS pod replicas share the same cache.
        // Before: bookingCache.put((String) booking.get("bookingId"), booking);
        // After:  redisTemplate.opsForValue().set(...)  [Externalized to ElastiCache for Redis]
        redisTemplate.opsForValue().set(
                "booking:" + booking.get("bookingId"),
                booking
        );

        Map<String, Object> response = new HashMap<>();
        response.put("status", "confirmed");
        response.put("booking", booking);
        response.put("sessionId", session.getId());
        return response;
    }

    @GetMapping("/status/{bookingId}")
    public Map<String, Object> getBookingStatus(
            @PathVariable String bookingId,
            // FIX cz-java-0069 (Lines 34-35): Replaced HttpSession parameter with
            // @RequestHeader session ID resolved via Spring Session / Redis.
            // Reading session attributes from Amazon ElastiCache ensures consistent
            // state across all EKS pod replicas regardless of which pod handles the request.
            @RequestHeader(value = "X-Auth-Token", required = false) String sessionId) {

        // FIX cz-java-0069: Read session attributes from Redis-backed Spring Session
        // instead of in-memory HttpSession. Returns consistent data across all EKS pods.
        String lastGuest = null;
        if (sessionId != null) {
            Session session = sessionRepository.findById(sessionId);
            if (session != null) {
                lastGuest = (String) session.getAttribute("guestName");
            }
        }

        Map<String, Object> result = new HashMap<>();
        result.put("bookingId", bookingId);
        result.put("sessionGuest", lastGuest);
        result.put("details", bookingService.getBookingById(bookingId));
        return result;
    }

    @GetMapping("/availability")
    public Map<String, Object> checkAvailability(@RequestParam String roomType) {
        // VIOLATION cr-java-0088 [Cloud Compatibility / Mandatory]: Plain HTTP call to
        // internal inventory service. AWS ALB, WAF, and Well-Architected security review
        // enforce HTTPS. This call will be blocked or flagged in a cloud-native setup.
        String inventoryUrl = "http://inventory-service.internal:8081/rooms/available"; // cr-java-0088

        Map<String, Object> response = new HashMap<>();
        response.put("roomType", roomType);
        response.put("inventoryEndpoint", inventoryUrl);
        response.put("available", bookingService.isRoomAvailable(roomType));
        return response;
    }

    @GetMapping("/report/download")
    public Map<String, Object> downloadReport(@RequestParam String month) {
        // FIX cz-java-0057: Replaced hardcoded absolute path /var/legacy/reports/ with
        // environment variable REPORT_BASE_PATH injected via Kubernetes ConfigMap on EKS.
        String reportPath = reportBasePath + "/" + month + "_bookings.pdf";

        Map<String, Object> response = new HashMap<>();
        response.put("reportPath", reportPath);
        response.put("message", bookingService.generateReport(month));
        return response;
    }

    /**
     * Helper method to save a session using a bounded type parameter, which resolves
     * the Java wildcard capture issue when calling save() on
     * SessionRepository&lt;? extends Session&gt;.
     */
    @SuppressWarnings("unchecked")
    private <S extends Session> void saveSession(Session session) {
        ((SessionRepository<S>) sessionRepository).save((S) session);
    }
}
