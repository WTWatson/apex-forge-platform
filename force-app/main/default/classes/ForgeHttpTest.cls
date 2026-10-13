@IsTest
private class ForgeHttpTest {

    private static final String SYSTEM_NAME = 'ForgeTestSystem';

    private class Customer
    {
        public String name;
        public String city;

        Customer(String name, String city)
        {
            this.name = name;
            this.city = city;
        }
    }

    private class CustomerNumber
    {
        public String customerNumber;
    }

    /** Remembers each request it is asked about, and stops any request when told to. */
    private class RememberRequests implements ForgeHttp.RequestCheck
    {
        private final List<String> asked = new List<String>();
        private Boolean stopsRequests = false;

        public void beforeSending(String method, Integer timeoutSeconds)
        {
            asked.add(method + ' ' + timeoutSeconds);
            if (stopsRequests) { throw new IllegalArgumentException('stopped'); }
        }
    }

    @IsTest
    static void getReturnsStatusBodyAndHeaders()
    {
        ForgeHttpMock.connection(SYSTEM_NAME).get('/customers/C-1').reply(200, '{"customerNumber":"C-1"}');

        Test.startTest();
        ForgeHttp.Response response = ForgeHttp.connection(SYSTEM_NAME).get('/customers/C-1');
        Test.stopTest();

        Assert.areEqual(200, response.status);
        Assert.areEqual('{"customerNumber":"C-1"}', response.body);
        Assert.areEqual('application/json', response.headers.get('Content-Type'));
        Assert.isTrue(response.isSuccess());
    }

    @IsTest
    static void postSendsAnObjectAsJson()
    {
        ForgeHttpMock.Route customers = ForgeHttpMock.connection(SYSTEM_NAME).post('/customers').reply(201, '');

        Test.startTest();
        ForgeHttp.connection(SYSTEM_NAME).post('/customers', new Customer('Acme Ltd', null));
        Test.stopTest();

        HttpRequest sent = customers.requests()[0];
        Assert.areEqual('callout:ForgeTestSystem/customers', sent.getEndpoint());
        Assert.areEqual('{"name":"Acme Ltd"}', sent.getBody(), 'null fields are left out');
        Assert.areEqual('application/json', sent.getHeader('Content-Type'));
    }

    @IsTest
    static void postSendsATextBodyUnchanged()
    {
        ForgeHttpMock.Route notes = ForgeHttpMock.connection(SYSTEM_NAME).post('/notes').reply(201, '');

        Test.startTest();
        ForgeHttp.connection(SYSTEM_NAME).post('/notes', 'name=Acme');
        Test.stopTest();

        Assert.areEqual('name=Acme', notes.requests()[0].getBody());
        Assert.isNull(notes.requests()[0].getHeader('Content-Type'), 'text is not labelled as JSON');
    }

    @IsTest
    static void putPatchAndRemoveUseTheirMethods()
    {
        ForgeHttpMock.ConnectionAnswers erp = ForgeHttpMock.connection(SYSTEM_NAME);
        ForgeHttpMock.Route replaced = erp.put('/customers/C-1').reply(200, '');
        ForgeHttpMock.Route changed = erp.patch('/customers/C-1').reply(200, '');
        ForgeHttpMock.Route removed = erp.remove('/customers/C-1').reply(204, '');

        Test.startTest();
        ForgeHttp.Connection connection = ForgeHttp.connection(SYSTEM_NAME);
        connection.put('/customers/C-1', new Customer('Acme Ltd', 'Leeds'));
        connection.patch('/customers/C-1', new Customer(null, 'York'));
        ForgeHttp.Response deleted = connection.remove('/customers/C-1');
        Test.stopTest();

        Assert.areEqual('PUT', replaced.requests()[0].getMethod());
        Assert.areEqual('{"city":"York"}', changed.requests()[0].getBody());
        Assert.areEqual('DELETE', removed.requests()[0].getMethod());
        Assert.areEqual(204, deleted.status);
    }

    @IsTest
    static void aConnectionWaitsThirtySecondsUnlessToldOtherwise()
    {
        Assert.areEqual(30, ForgeHttp.connection(SYSTEM_NAME).timeoutSeconds());
        Assert.areEqual(5, ForgeHttp.connection(SYSTEM_NAME).waitsUpToSeconds(5).timeoutSeconds());
    }

    @IsTest
    static void readAsReadsTheJsonIntoTheGivenType()
    {
        ForgeHttpMock.connection(SYSTEM_NAME).post('/customers')
            .reply(201, '[{"customerNumber":"C-1001"},{"customerNumber":"C-1002"}]');

        Test.startTest();
        List<CustomerNumber> numbers = (List<CustomerNumber>) ForgeHttp.connection(SYSTEM_NAME)
            .post('/customers', new List<Customer>{ new Customer('Acme Ltd', null), new Customer('Bolt plc', null) })
            .readAs(List<CustomerNumber>.class);
        Test.stopTest();

        Assert.areEqual(2, numbers.size());
        Assert.areEqual('C-1001', numbers[0].customerNumber);
        Assert.areEqual('C-1002', numbers[1].customerNumber);
    }

    @IsTest
    static void twoHundredCustomersGoInOneCallAndComeBackInOrder()
    {
        List<Customer> customers = new List<Customer>();
        List<String> reply = new List<String>();
        for (Integer i = 0; i < 200; i++)
        {
            customers.add(new Customer('Customer ' + i, null));
            reply.add('{"customerNumber":"C-' + i + '"}');
        }
        ForgeHttpMock.Route route = ForgeHttpMock.connection(SYSTEM_NAME).post('/customers')
            .reply(201, '[' + String.join(reply, ',') + ']');

        Test.startTest();
        List<CustomerNumber> numbers = (List<CustomerNumber>) ForgeHttp.connection(SYSTEM_NAME)
            .post('/customers', customers)
            .readAs(List<CustomerNumber>.class);
        Test.stopTest();

        Assert.areEqual(1, route.requests().size());
        Assert.areEqual(200, ((List<Object>) JSON.deserializeUntyped(route.requests()[0].getBody())).size());
        Assert.areEqual(200, numbers.size());
        Assert.areEqual('C-199', numbers[199].customerNumber);
    }

    @IsTest
    static void aReplyOutsideTwoHundredsRaisesAFailureWithItsDetails()
    {
        ForgeHttpMock.connection(SYSTEM_NAME).post('/customers').reply(400, '{"error":"name is required"}');

        Test.startTest();
        ForgeHttp.CalloutFailureException failure;
        try
        {
            ForgeHttp.connection(SYSTEM_NAME).post('/customers', new Customer(null, null));
        }
        catch (ForgeHttp.CalloutFailureException raised)
        {
            failure = raised;
        }
        Test.stopTest();

        Assert.isNotNull(failure, 'a 400 reply raises a failure');
        Assert.areEqual('POST', failure.method);
        Assert.areEqual('/customers', failure.path);
        Assert.areEqual(400, failure.status);
        Assert.areEqual('{"error":"name is required"}', failure.replyBody);
        Assert.areEqual('POST /customers failed with status 400', failure.getMessage());
        Assert.isFalse(failure.isWorthRetrying(), 'a 400 will fail the same way again');
    }

    @IsTest
    static void unavailableAndTimedOutAreWorthRetrying()
    {
        ForgeHttpMock.ConnectionAnswers erp = ForgeHttpMock.connection(SYSTEM_NAME);
        erp.get('/busy').reply(503, 'Service Unavailable');
        erp.get('/gateway').reply(502, '');
        erp.get('/slow').timesOut();

        Test.startTest();
        ForgeHttp.CalloutFailureException busy = failureOf('/busy');
        ForgeHttp.CalloutFailureException gateway = failureOf('/gateway');
        ForgeHttp.CalloutFailureException slow = failureOf('/slow');
        Test.stopTest();

        Assert.isTrue(busy.isWorthRetrying());
        Assert.isTrue(gateway.isWorthRetrying());
        Assert.isTrue(slow.isWorthRetrying());
        Assert.isNull(slow.status, 'a timeout has no status');
        Assert.areEqual('GET /slow failed with a timeout', slow.getMessage());
    }

    @IsTest
    static void acceptingAnyStatusHandsBackTheReplyAsItCame()
    {
        ForgeHttpMock.connection(SYSTEM_NAME).get('/customers/C-9').reply(404, 'not found');

        Test.startTest();
        ForgeHttp.Response response = ForgeHttp.connection(SYSTEM_NAME).acceptingAnyStatus().get('/customers/C-9');
        Test.stopTest();

        Assert.areEqual(404, response.status);
        Assert.areEqual('not found', response.body);
        Assert.isFalse(response.isSuccess());
    }

    @IsTest
    static void answersComeInOrderAndTheLastOneRepeats()
    {
        ForgeHttpMock.Route customers = ForgeHttpMock.connection(SYSTEM_NAME).get('/customers')
            .reply(503, '')
            .reply(200, '[]');

        Test.startTest();
        ForgeHttp.Connection connection = ForgeHttp.connection(SYSTEM_NAME).acceptingAnyStatus();
        Integer first = connection.get('/customers').status;
        Integer second = connection.get('/customers').status;
        Integer third = connection.get('/customers').status;
        Test.stopTest();

        Assert.areEqual(503, first);
        Assert.areEqual(200, second);
        Assert.areEqual(200, third);
        Assert.areEqual(3, customers.requests().size());
    }

    @IsTest
    static void aRequestNoTestDescribedFailsWithTheRequestItSaw()
    {
        ForgeHttpMock.connection(SYSTEM_NAME).get('/customers').reply(200, '[]');

        Test.startTest();
        ForgeHttpMock.UnmatchedRequestException unmatched;
        try
        {
            ForgeHttp.connection(SYSTEM_NAME).post('/orders', 'order=1');
        }
        catch (ForgeHttpMock.UnmatchedRequestException raised)
        {
            unmatched = raised;
        }
        Test.stopTest();

        Assert.isNotNull(unmatched, 'an undescribed request fails');
        Assert.areEqual('No answer described for POST callout:ForgeTestSystem/orders with body: order=1',
            unmatched.getMessage());
    }

    @IsTest
    static void anIdempotencyKeyIsSentAndEachLaterRequestNumbersIt()
    {
        ForgeHttpMock.Route orders = ForgeHttpMock.connection(SYSTEM_NAME).post('/orders').reply(201, '');

        Test.startTest();
        ForgeHttp.Connection erp = ForgeHttp.connection(SYSTEM_NAME).idempotencyKey('order-7');
        erp.post('/orders', 'first');
        erp.post('/orders', 'second');
        ForgeHttp.connection(SYSTEM_NAME).post('/orders', 'no key');
        Test.stopTest();

        Assert.areEqual('order-7', orders.requests()[0].getHeader('Idempotency-Key'));
        Assert.areEqual('order-7-2', orders.requests()[1].getHeader('Idempotency-Key'));
        Assert.isNull(orders.requests()[2].getHeader('Idempotency-Key'), 'no key unless one is given');
    }

    @IsTest
    static void waitsUpToSecondsSetsTheTimeoutTheRequestIsSentWith()
    {
        ForgeHttpMock.connection(SYSTEM_NAME).get('/customers/C-1').reply(200, '');
        RememberRequests check = new RememberRequests();

        Test.startTest();
        ForgeHttp.Connection erp = ForgeHttp.connection(SYSTEM_NAME).checkingEachRequestWith(check);
        erp.waitsUpToSeconds(60);
        erp.get('/customers/C-1');
        Test.stopTest();

        // HttpRequest has no getter for its timeout; the check is given the value the request was set to.
        Assert.areEqual(new List<String>{ 'GET 60' }, check.asked, 'the timeout is read when the request is sent');
    }

    @IsTest
    static void aRequestTheCheckStopsIsNotSent()
    {
        ForgeHttpMock.Route customers = ForgeHttpMock.connection(SYSTEM_NAME).post('/customers').reply(201, '');
        RememberRequests check = new RememberRequests();
        check.stopsRequests = true;

        Test.startTest();
        try
        {
            ForgeHttp.connection(SYSTEM_NAME).checkingEachRequestWith(check).post('/customers', 'Acme');
            Assert.fail('the check stops the request');
        }
        catch (IllegalArgumentException stopped)
        {
            Assert.areEqual('stopped', stopped.getMessage());
        }
        Test.stopTest();

        Assert.areEqual(0, customers.requests().size());
    }

    private static ForgeHttp.CalloutFailureException failureOf(String path)
    {
        try
        {
            ForgeHttp.connection(SYSTEM_NAME).get(path);
        }
        catch (ForgeHttp.CalloutFailureException failure)
        {
            return failure;
        }
        Assert.fail('GET ' + path + ' should have failed');
        return null;
    }
}
