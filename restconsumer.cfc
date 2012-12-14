<cfcomponent name="RestConsumer" output="false" hint="Wrapper for interacting with RESTful APIs">

	<!--- use this java object to get at the current RequestTimeout value for a given request --->
	<cfset variables.rcMonitor = createObject("java", "coldfusion.runtime.RequestMonitor") />
	<cfset variables.debug = false />
	<cfset variables.rate_limit_per_second = 0 />
	<cfset variables.rate_limit_requests = arrayNew(1) />

	<cffunction name="init" access="public" output="false" returntype="any">
		<cfreturn this />
	</cffunction>

	<!--- wrappers with CRUD naming --->
	<cffunction name="get" output="false" access="public" returntype="any" hint="Used to retrieve resources without making changes">
		<cfreturn process(argumentCollection = arguments, method = "get") />		
	</cffunction>

	<cffunction name="post" output="false" access="public" returntype="any" hint="Generally used to create resources">
		<cfreturn process(argumentCollection = arguments, method = "post") />		
	</cffunction>
	
	<cffunction name="put" output="false" access="public" returntype="any" hint="Generally used to update resources">
		<cfreturn process(argumentCollection = arguments, method = "put") />		
	</cffunction>
	
	<cffunction name="delete" output="false" access="public" returntype="any" hint="Used to delete resources">
		<cfreturn process(argumentCollection = arguments, method = "delete") />		
	</cffunction>

	<cffunction name="head" output="false" access="public" returntype="any" hint="Returns the same data as a GET request without the representation">
		<cfreturn process(argumentCollection = arguments, method = "head") />		
	</cffunction>


	<!--- Usage: Process the HTTP request --->
	<cffunction name="process" output="false" access="public" returntype="struct" hint="Robust HTTP get/post/put/delete mechanism with error handling">
		<cfargument name="url" type="string" required="true" />
		<cfargument name="method" type="any" required="false" default="post" hint="GET, POST, PUT, DELETE, HEAD, TRACE, ..." />
		<cfargument name="payload" type="any" required="false" default="#structNew()#" />
		<cfargument name="headers" type="struct" required="false" default="#structNew()#" />
		<cfargument name="timeout" type="numeric" required="false" default="0" />

		<!--- prepare response before attempting to send over wire --->
		<cfset var response = {complete = false, status = 0, headers = structNew(), content = ""} />
		<cfset var CFHTTP = "" />

		<!--- enable a little extra time past the CFHTTP timeout so error handlers can run --->
		<cfif NOT structKeyExists(arguments, "timeout") OR arguments.timeout NEQ 0>
			<cfset arguments.timeout = getCurrentRequestTimeout() + 15 />
		</cfif>

		<cfsetting requesttimeout="#timeout#" />

		<!--- check the rate limit to see if we need to delay --->
		<cfset verifyAndRespectRateLimit() />

		<cftry>

			<cfset CFHTTP = doHttpCall(argumentCollection = arguments) />

			<!--- begin result handling --->
			<cfif isDefined("CFHTTP") AND isStruct(CFHTTP) AND structKeyExists(CFHTTP, "fileContent") AND structKeyExists(CFHTTP, "responseHeader") AND structKeyExists(CFHTTP.responseHeader,  "status_code")>
				<cfset response.complete = true />
				<cfset response.content = trim(cfhttp.fileContent) />
				<cfset response.headers = cfhttp.responseHeader />
				<cfset response.status = cfhttp.responseHeader.status_code /><!--- if wonky, use old standby: reReplace(cfhttp.statusCode, "[^0-9]", "", "ALL") --->
			</cfif>

			<!--- if all went well, return the struct now --->
			<cfreturn response />

			<cfcatch type="COM.Allaire.ColdFusion.HTTPFailure">
				<!--- ColdFusion wasn't able to connect successfully.  This can be an expired, not legit or self-signed SSL cert. --->
				<cfreturn response />
			</cfcatch>
			<cfcatch type="coldfusion.runtime.RequestTimedOutException">
				<cfset response.content = "Request timed out" />
				<cfreturn response />
			</cfcatch>
			<cfcatch type="any">
				<!--- something we don't yet have an exception for --->
				<cfset response.content = cfcatch.Message />
				<cfreturn response />
			</cfcatch>

		</cftry>

		<!--- return raw collection to be handled --->
		<cfreturn response />
	</cffunction>


	<cffunction name="doHttpCall" access="private" hint="wrapper around the http call - improves testing" returntype="struct" output="false">
		<cfargument name="url" type="string" required="true" hint="resource to access" />
		<cfargument name="method" type="string" required="false" hint="the http request method" default="get" />
		<cfargument name="timeout" type="numeric" required="true" />
		<cfargument name="headers" type="struct" required="false" default="#structNew()#" />
		<cfargument name="payload" type="any" required="false" default="#structNew()#" />

		<cfset var CFHTTP = "" />
		<cfset var key = "" />
		<cfset var paramType = "" />

		<cfif ucase(arguments.method) EQ "GET">
			<cfset paramType = "url" />
		<cfelseif ucase(arguments.method) EQ "POST">
			<cfset paramType = "formfield" />
		<cfelseif ucase(arguments.method) EQ "PUT">
			<cfset paramType = "body" />
		<cfelseif ucase(arguments.method) EQ "DELETE">
			<cfset paramType = "body" />
		<cfelse>
			<cfthrow message="Invalid Method" type="RestConsumer.InvalidParameter.Method" detail="The HTTP method #arguments.method# is not supported by RestConsumer" />
		</cfif>

		<!--- log request parameters if necessary --->
		<cfif variables.debug>
			<cfdump var="#uCase(arguments.method)# #arguments.url#" output="console" label="Request URL" />
			<cfdump var="#arguments.headers#" output="console" label="Request Headers" />
			<cfdump var="#arguments.payload#" output="console" label="Request Payload for type '#paramType#'" />
		</cfif>

		<!--- send request; do not use username/password on the tag as if they are blank, it jacks up the headers for HMAC signed services; build the header by hand --->
		<cftry>
			<cfhttp url="#arguments.url#" method="#arguments.method#" timeout="#timeout#" throwonerror="no" charset="utf-8">
				<!--- pass along any extra headers, like Accept or Authorization --->
				<cfloop collection="#arguments.headers#" item="key">
					<cfhttpparam name="#key#" value="#arguments.headers[key]#" type="header" />
				</cfloop>
				
				<!--- we can serialize as xml, json or even hand-build a www-form-encoded string, so basically it's either simple value as body or struct we loop over? 
				<cfif paramType EQ "body">
					<!--- make sure we have a payload we can post --->
					<cfif NOT isSimpleValue(arguments.payload)>
						<cfthrow errorcode="RestConsumer.UnsupportedPayload" message="This type of request requires a simple payload.  Consider serializing the payload to XML or JSON first." />
					</cfif>
					<cfhttpparam value="#arguments.payload#" type="body" />--->
				<cfif isStruct(arguments.payload)>
					<cfloop collection="#arguments.payload#" item="key">
						<cfhttpparam name="#key#" value="#arguments.payload[key]#" type="#paramType#" />
					</cfloop>
				<cfelseif isSimpleValue(arguments.payload) AND len(arguments.payload)>
					<cfhttpparam value="#arguments.payload#" type="body" />
				</cfif>
			</cfhttp>
			
			<cfif variables.debug>
				<cfdump var="#cfhttp#" output="console" label="Response CFHTTP" />
			</cfif>
			
			<cfcatch type="any">
				<cfdump var="#cfcatch.Message# / #cfcatch.Detail#" output="console" label="CFCATCH Error" />
				<cfdump var="#cfcatch.TagContext#" output="console" label="CFCATCH TagContext" />
				<cfrethrow />
			</cfcatch>
		</cftry>
			
		<cfreturn CFHTTP />
	</cffunction>


	<cffunction name="getCurrentRequestTimeout" output="false" access="private" returntype="numeric">
		<cftry>
			<cfreturn variables.rcMonitor.getRequestTimeout() />
			<cfcatch type="any">
				<cfthrow message="Request Context Monitor Disabled" detail="The rcMonitor is disabled preventing access to the current request timeout setting" />
			</cfcatch>
		</cftry>
	</cffunction>


	<cffunction name="setDebug" output="false" access="public" returntype="void">
		<cfargument name="debug" type="boolean" required="true" />
		<cfset variables.debug = arguments.debug />
	</cffunction>


	<cffunction name="setRateLimit" output="false" access="public" returntype="void">
		<cfargument name="ratelimit" type="any" required="true" hint="The number of requests allowed per second" />
		<cfset variables.rate_limit_per_second = arguments.ratelimit />
	</cffunction>


	<cffunction name="verifyAndRespectRateLimit" output="false" access="public" returntype="void">
		<cfset var wait = "" />
	
		<cfif variables.rate_limit_per_second EQ 0><cfexit /></cfif>
	
		<cflock name="restconsumer_checking_for_ratelimit_cap" type="exclusive" timeout="5">

			<!--- now clean up stuff older than 1 second ago --->
			<cfloop condition="arrayLen(variables.rate_limit_requests)">
				<cfif (getTickCount() - variables.rate_limit_requests[1]) GT 1000>
					<cfset arrayDeleteAt(variables.rate_limit_requests, 1 ) />
				<cfelse>
					<cfbreak />
				</cfif>
			</cfloop>

			<cfif arrayLen(variables.rate_limit_requests) GTE variables.rate_limit_per_second>
				<cfset wait = 1000 - (getTickCount() - variables.rate_limit_requests[1]) />
				<cfif variables.debug>
					<cflog file="application" text="Throttling request ###arrayLen(variables.rate_limit_requests)# #wait#ms (> #variables.rate_limit_per_second# per second)" />
				</cfif>
				<cfset createObject("java", "java.lang.Thread").sleep(wait) />
			</cfif>

			<!--- log the hit (do this after so we only throttle if we're already at the limit as opposed to this request putting us over) --->
			<cfset arrayAppend(variables.rate_limit_requests, getTickCount()) />
		
		</cflock>	
	</cffunction>


</cfcomponent>