/**
 * This file is part of the Forge Platform project
 *
 * Calls another system through a Named Credential: the request is built, the body
 * turned to JSON and the status checked here, so the caller writes only what the
 * integration means.
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
public with sharing class ForgeHttp {

    private static final Integer DEFAULT_TIMEOUT_SECONDS = 30;
    private static final Set<Integer> RETRYABLE_STATUSES = new Set<Integer>{ 502, 503, 504 };

    /** Opens a connection to the system behind the Named Credential with this name. */
    public static Connection connection(String namedCredential)
    {
        return new Connection(namedCredential);
    }

    /** A connection to one other system, reached through its Named Credential. */
    public class Connection
    {
        private final String namedCredential;
        private Integer waitSeconds = DEFAULT_TIMEOUT_SECONDS;
        private Boolean acceptsAnyStatus = false;
        private String idempotencyKey;
        private Integer requestsSent = 0;
        private Response lastReply;
        private RequestCheck check;

        private Connection(String namedCredential)
        {
            this.namedCredential = namedCredential;
        }

        /** Waits this many seconds for the other system to answer before giving up; 30 unless set. */
        public Connection waitsUpToSeconds(Integer seconds)
        {
            this.waitSeconds = seconds;
            return this;
        }

        /** How many seconds this connection waits for an answer before giving up. */
        public Integer timeoutSeconds()
        {
            return waitSeconds;
        }

        /** Asks this check before each request is sent, with the timeout the request will have; ForgeIntegration uses it to keep a job inside its callout limits. */
        public Connection checkingEachRequestWith(RequestCheck check)
        {
            this.check = check;
            return this;
        }

        /** Sends this key as the Idempotency-Key header, so a system that honours it acts on a repeated request only once; later requests on the connection get the key with their number appended. */
        public Connection idempotencyKey(String key)
        {
            this.idempotencyKey = key;
            return this;
        }

        /** The last answer the other system gave on this connection, or null before the first. */
        public Response lastReply()
        {
            return lastReply;
        }

        /** Hands back every reply as it came, instead of raising a failure for a status outside 200 to 299. */
        public Connection acceptingAnyStatus()
        {
            this.acceptsAnyStatus = true;
            return this;
        }

        /** Reads what the other system holds at this path. */
        public Response get(String path)
        {
            return send('GET', path, null);
        }

        /** Sends this body to the other system at this path to create something. */
        public Response post(String path, Object body)
        {
            return send('POST', path, body);
        }

        /** Sends this body to the other system at this path to replace what is there. */
        public Response put(String path, Object body)
        {
            return send('PUT', path, body);
        }

        /** Sends this body to the other system at this path to change part of what is there. */
        public Response patch(String path, Object body)
        {
            return send('PATCH', path, body);
        }

        /** Asks the other system to remove what it holds at this path. */
        public Response remove(String path)
        {
            return send('DELETE', path, null);
        }

        private Response send(String method, String path, Object body)
        {
            if (check != null) { check.beforeSending(method, waitSeconds); }
            Response response;
            try
            {
                response = new Response(new Http().send(buildRequest(method, path, body)));
                lastReply = response;
            }
            catch (CalloutException timeout)
            {
                if (!timeout.getMessage().containsIgnoreCase('timed out')) { throw timeout; }
                throw new CalloutFailureException(method, path, null, timeout.getMessage());
            }

            if (!acceptsAnyStatus && !response.isSuccess())
            {
                throw new CalloutFailureException(method, path, response.status, response.body);
            }
            return response;
        }

        private HttpRequest buildRequest(String method, String path, Object body)
        {
            HttpRequest request = new HttpRequest();
            request.setMethod(method);
            request.setEndpoint('callout:' + namedCredential + path);
            request.setTimeout(waitSeconds * 1000);
            requestsSent++;
            if (idempotencyKey != null)
            {
                request.setHeader('Idempotency-Key', requestsSent == 1 ? idempotencyKey : idempotencyKey + '-' + requestsSent);
            }

            if (body instanceof String)
            {
                request.setBody((String) body);
            }
            else if (body != null)
            {
                request.setBody(JSON.serialize(body, true));
                request.setHeader('Content-Type', 'application/json');
            }
            return request;
        }
    }

    /** Decides whether a request may be sent, just before it is. */
    public interface RequestCheck
    {
        /** Called with the method and the timeout in seconds of the request about to be sent; throws to stop it. */
        void beforeSending(String method, Integer timeoutSeconds);
    }

    /** What the other system answered: its status, body and headers. */
    public class Response
    {
        /** The HTTP status the other system answered with, such as 200 or 404. */
        public final Integer status;
        /** The body of the answer as text. */
        public final String body;
        /** The headers of the answer, by name. */
        public final Map<String, String> headers = new Map<String, String>();

        private Response(HttpResponse reply)
        {
            this.status = reply.getStatusCode();
            this.body = reply.getBody();
            for (String name : reply.getHeaderKeys())
            {
                if (name != null) { headers.put(name, reply.getHeader(name)); }
            }
        }

        /** Reads the JSON body as the given Apex type, such as List<CustomerNumber>.class. */
        public Object readAs(Type shape)
        {
            return JSON.deserialize(body, shape);
        }

        /** Tells whether the status is between 200 and 299. */
        public Boolean isSuccess()
        {
            return status >= 200 && status <= 299;
        }
    }

    /** Raised when the other system answers outside 200 to 299 or does not answer in time. */
    public class CalloutFailureException extends Exception
    {
        /** The method of the request that failed, such as POST. */
        public String method { get; private set; }
        /** The path of the request that failed, after the Named Credential. */
        public String path { get; private set; }
        /** The status the other system answered with; null when it did not answer in time. */
        public Integer status { get; private set; }
        /** The body the other system answered with, or the timeout message. */
        public String replyBody { get; private set; }

        private CalloutFailureException(String method, String path, Integer status, String replyBody)
        {
            this(method + ' ' + path + ' failed with ' + (status == null ? 'a timeout' : 'status ' + status));
            this.method = method;
            this.path = path;
            this.status = status;
            this.replyBody = replyBody;
        }

        /** Tells whether trying the same call again later may succeed: a timeout, 502, 503 or 504. */
        public Boolean isWorthRetrying()
        {
            return status == null || RETRYABLE_STATUSES.contains(status);
        }
    }
}
