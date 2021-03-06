RequestParser = require "./RequestParser"
CompileManager = require "./CompileManager"
Settings = require "settings-sharelatex"
Metrics = require "./Metrics"
ProjectPersistenceManager = require "./ProjectPersistenceManager"
logger = require "logger-sharelatex"

module.exports = CompileController =
	compile: (req, res, next = (error) ->) ->
		timer = new Metrics.Timer("compile-request")
		bod = req.body
		logger.info {bod}, "compile request body"
		
		RequestParser.parse req.body, (error, request) ->
			return next(error) if error?
			request.project_id = req.params.project_id
			request.user_id = req.params.user_id if req.params.user_id?
			request.csrf = req.body.compile.csrf
			request.folder_id = req.body.compile.folder_id
			ProjectPersistenceManager.markProjectAsJustAccessed request.project_id, (error) ->
				return next(error) if error?
				CompileManager.doCompile request, (error, outputFiles = []) ->
					if error?.terminated
						status = "terminated"
					else if error?.validate
						status = "validation-#{error.validate}"
					else if error?
						if error.timedout
							status = "timedout"
							logger.log err: error, project_id: request.project_id, "timeout running compile"
						else
							status = "error"
							code = 500
							logger.error err: error, project_id: request.project_id, "error running compile"
					else
						status = "failure"
						for file in outputFiles
							if file.path?.match(/output\.pdf$/) || file.path?.match(/output\.txt$/)
								status = "success"

					timer.done()
					res.status(code or 200).send {
						compile:
							status: status
							error:  error?.message or error
							outputFiles: outputFiles.map (file) ->
								url:
									"#{Settings.apis.clsi.url}/project/#{request.project_id}" +
									(if request.user_id? then "/user/#{request.user_id}" else "") +
									(if file.build? then "/build/#{file.build}" else "") +
									"/output/#{file.path}"
								path: file.path
								type: file.type
								build: file.build
					}

	stopCompile: (req, res, next) ->
		{project_id, user_id} = req.params
		CompileManager.stopCompile project_id, user_id, (error) ->
			return next(error) if error?
			res.sendStatus(204)

	clearCache: (req, res, next = (error) ->) ->
		ProjectPersistenceManager.clearProject req.params.project_id, req.params.user_id, (error) ->
			return next(error) if error?
			res.sendStatus(204) # No content

	syncFromCode: (req, res, next = (error) ->) ->
		file   = req.query.file
		line   = parseInt(req.query.line, 10)
		column = parseInt(req.query.column, 10)
		project_id = req.params.project_id
		user_id = req.params.user_id

		CompileManager.syncFromCode project_id, user_id, file, line, column, (error, pdfPositions) ->
			return next(error) if error?
			res.send JSON.stringify {
				pdf: pdfPositions
			}

	syncFromPdf: (req, res, next = (error) ->) ->
		page   = parseInt(req.query.page, 10)
		h      = parseFloat(req.query.h)
		v      = parseFloat(req.query.v)
		project_id = req.params.project_id
		user_id = req.params.user_id

		CompileManager.syncFromPdf project_id, user_id, page, h, v, (error, codePositions) ->
			return next(error) if error?
			res.send JSON.stringify {
				code: codePositions
			}

	wordcount: (req, res, next = (error) ->) ->
		file   = req.query.file || "main.tex"
		project_id = req.params.project_id
		user_id = req.params.user_id
		image = req.query.image
		logger.log {image, file, project_id}, "word count request"

		CompileManager.wordcount project_id, user_id, file, image, (error, result) ->
			return next(error) if error?
			res.send JSON.stringify {
				texcount: result
			}

	status: (req, res, next = (error)-> )->
		res.send("OK")

