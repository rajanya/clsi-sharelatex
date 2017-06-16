Path  = require "path"
async = require "async"
Settings = require "settings-sharelatex"
request = require('request')
fs = require('fs')
logger = require "logger-sharelatex"
Url = require("url")
_ = require("underscore")
async = require("async")

module.exports = FileUploadManager =

	sendRequest: (project_id, user_id, folder_id, options = {}, callback = (error, status) ->) ->
		
		FileUploadManager._postToWeb project_id, user_id, folder_id, options, (error, response) ->
			if error?
				logger.err err:error, project_id:project_id, "error sending request to Web"
				return callback(error)
			logger.log project_id: project_id, status: response?.status, "received upload response from Web"
			callback(null, response?.status)


	_makeRequest: (project_id, opts, callback)->

		request opts, (err, response, body)->
			if err?
				logger.err err:err, project_id:project_id, url:opts?.url, "error making request to Web"
				return callback(err)
			return callback err, response, body

	_getUploadFileUrl: (project_id, folder_id) ->
		host = Settings.apis.web.url
		path = "/project/#{project_id}/upload?folder_id=#{folder_id}"
		return "#{host}#{path}"

	_postToWeb: (project_id, user_id, folder_id, options, callback = (error, response) ->) ->
		uploadFileUrl = @_getUploadFileUrl(project_id, folder_id)
		headers = {}
		#headers['x-csrf-token'] = csrfToken
		headers['Content-Type'] = 'multipart/form-data'
		headers['x-requested-with'] = 'XMLHttpRequest'
		headers['accept'] = '/' 
		
		formData = {
			qqfile: fs.createReadStream(options.path),
			user: user_id
		}
		
		opts =
			url:  uploadFileUrl
			headers: headers
			formData: formData
			method: "POST"
		FileUploadManager._makeRequest project_id, opts, (error, response, body) ->
			return callback(error) if error?
			if 200 <= response.statusCode < 300
				callback null, body
			else if response.statusCode == 413
				callback null, compile:status:"project-too-large"
			else
				error = new Error("Web returned non-success code: #{response.statusCode}")
				logger.error err: error, project_id: project_id, "Web returned failure code"
				callback error, body