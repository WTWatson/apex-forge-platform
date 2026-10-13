/**
 * This file is part of the Forge Platform project
 *
 * Stands in for other systems in tests: a test says what each connection answers
 * to a method and path, and every callout gets that answer, with no mock class to
 * write. A request nobody described fails the test with the request it saw.
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
@IsTest
public with sharing class ForgeHttpMock implements HttpCalloutMock {

    private static final Map<String, Route> routes = new Map<String, Route>();
    private static Boolean installed = false;

    /** Starts describing how the system behind the Named Credential with this name answers. */
    public static ConnectionAnswers connection(String namedCredential)
    {
        if (!installed)
        {
            Test.setMock(HttpCalloutMock.class, new ForgeHttpMock());
            installed = true;
        }
        return new ConnectionAnswers(namedCredential);
    }

    /** Answers one callout with the reply a test described for its connection, method and path. */
    public HttpResponse respond(HttpRequest request)
    {
        Route route = routes.get(routeKey(request.getMethod(), request.getEndpoint()));
        if (route == null || route.answers.isEmpty())
        {
            throw new UnmatchedRequestException('No answer described for ' + request.getMethod() + ' '
                + request.getEndpoint() + ' with body: ' + request.getBody());
        }
        return route.answer(request);
    }

    private static String routeKey(String method, String endpoint)
    {
        return method + ' ' + endpoint;
    }

    /** The answers one other system gives, by method and path. */
    public class ConnectionAnswers
    {
        private final String namedCredential;

        private ConnectionAnswers(String namedCredential)
        {
            this.namedCredential = namedCredential;
        }

        /** Describes how the system answers a GET to this path. */
        public Route get(String path) { return route('GET', path); }

        /** Describes how the system answers a POST to this path. */
        public Route post(String path) { return route('POST', path); }

        /** Describes how the system answers a PUT to this path. */
        public Route put(String path) { return route('PUT', path); }

        /** Describes how the system answers a PATCH to this path. */
        public Route patch(String path) { return route('PATCH', path); }

        /** Describes how the system answers a DELETE to this path. */
        public Route remove(String path) { return route('DELETE', path); }

        private Route route(String method, String path)
        {
            String key = routeKey(method, 'callout:' + namedCredential + path);
            if (!routes.containsKey(key)) { routes.put(key, new Route()); }
            return routes.get(key);
        }
    }

    /** The answers to one method and path, given in the order described; the last one repeats. */
    public class Route
    {
        private final List<Answer> answers = new List<Answer>();
        private final List<HttpRequest> received = new List<HttpRequest>();

        /** Adds an answer with this status and body. */
        public Route reply(Integer status, String body)
        {
            answers.add(new Answer(status, body));
            return this;
        }

        /** Adds an answer that never comes, as if the system did not reply in time. */
        public Route timesOut()
        {
            answers.add(new Answer(null, null));
            return this;
        }

        /** The requests this route has answered, oldest first, for checking what was sent. */
        public List<HttpRequest> requests()
        {
            return received;
        }

        private HttpResponse answer(HttpRequest request)
        {
            Integer turn = Math.min(received.size(), answers.size() - 1);
            received.add(request);
            return answers[turn].toResponse();
        }
    }

    private class Answer
    {
        private final Integer status;
        private final String body;

        private Answer(Integer status, String body)
        {
            this.status = status;
            this.body = body;
        }

        private HttpResponse toResponse()
        {
            if (status == null) { throw new CalloutException('Read timed out'); }

            HttpResponse response = new HttpResponse();
            response.setStatusCode(status);
            response.setBody(body == null ? '' : body);
            response.setHeader('Content-Type', 'application/json');
            return response;
        }
    }

    /** Raised when a callout reaches a connection, method and path no test described. */
    public class UnmatchedRequestException extends Exception {}
}
