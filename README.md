restconsumer
============

ColdFusion client for RESTful APIs

This component simply abstracts access to REST APIs providing some helper functions and a testable CFHTTP framework.

Compatible with at least CF8 and above.  Supports rate-limiting, debug dumps of requests and responses and returns
a simple structure of data for parsing.  

For use with my API clients or as a low-level REST API client.  Centralizes the (sometimes insane) error handling for CFHTTP and normalizes responses to assist with unit testing.

* https://github.com/ghidinelli/batchbook-api-coldfusion
* https://github.com/ghidinelli/eventful-api-coldfusion
* https://github.com/ghidinelli/hubspot-api-coldfusion
