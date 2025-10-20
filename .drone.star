config = {
	'name': 'libre-graph-api',
	'branches': [
		'main'
	],
	'languages': {
		'go': {
			'src': "out-go",
			'repo-slug': "libre-graph-api-go",
			'branch': 'main',
			'generator-args': "--api-name-suffix Api",
		},
		'typescript-axios': {
			'src': "out-typescript-axios",
			'repo-slug': "libre-graph-api-typescript-axios",
			'branch': 'main',
		},
		'cpp-qt-client': {
			'src': "out-cpp-qt-client",
			'repo-slug': "libre-graph-api-cpp-qt-client",
			'branch': 'main',
		},
		'php-nextgen': {
			'src': "out-php",
			'repo-slug': "libre-graph-api-php",
			'branch': 'main',
			'openapi-generator-image': 'openapitools/openapi-generator-cli@sha256:95ba4bf0bb5b219841c51a63e8776453b16cb93e74257cc65f781aa24472afda'
		},
	},
	'openapi-generator-image': 'openapitools/openapi-generator-cli:v7.8.0@sha256:18345ed78d64e2590481c6c4ed1d15e8a389156a38a289ba2960b0693ea69207',
}

def main(ctx):
	stages = stagePipelines(ctx)
	if (stages == False):
		print('Errors detected. Review messages above.')
		return []

	dependsOn(stages)
	return stages

def stagePipelines(ctx):
	linters = linting(ctx)
	generators = generate(ctx, "go") + generate(ctx, "typescript-axios") + generate(ctx, "cpp-qt-client") + generate(ctx, "php-nextgen")
	dependsOn(linters, generators)
	return linters + generators

def dependsOn(earlierStages, nextStages):
	for earlierStage in earlierStages:
		for nextStage in nextStages:
			nextStage['depends_on'].append(earlierStage['name'])

def linting(ctx):
	pipelines = []

	result = {
			'kind': 'pipeline',
			'type': 'docker',
			'name': 'lint',
			'steps': [
				{
					'name': 'validate',
					'image': config['openapi-generator-image'],
					'pull': 'always',
					'commands': [
						'/usr/local/bin/docker-entrypoint.sh validate -i api/openapi-spec/v1.0.yaml',
					],
				}
			],
			'depends_on': [],
			'trigger': {
				'ref': [
					'refs/pull/**',
					'refs/tags/**'
				]
			}
		}

	for branch in config['branches']:
		result['trigger']['ref'].append('refs/heads/%s' % branch)

	pipelines.append(result)

	return pipelines

def generate(ctx, lang):
	pipelines = []
	result = {
		'kind': 'pipeline',
		'type': 'docker',
		'name': 'generate-%s' % lang,
		'steps': [
			{
				"name": "clone-remote-%s" % lang,
				"image": "plugins/git-action:1",
				"pull": "always",
				"settings": {
					"actions": [
						"clone",
					],
					"remote": "https://github.com/owncloud/%s" % config["languages"][lang]["repo-slug"],
					"branch": "%s" % config["languages"][lang]["branch"],
					"path": "%s" % config["languages"][lang]["src"],
					"netrc_machine": "github.com",
					"netrc_username": {
						"from_secret": "github_username",
					},
					"netrc_password": {
						"from_secret": "github_token",
					},
				},
			},
			] + lint(lang) + [
			{
				'name': 'generate-%s' % lang,
				'image': getGeneratorImageVersion(lang),
				'pull': 'always',
				'commands': [
					'test -d "templates/{0}" && TEMPLATE_ARG="-t templates/{0}" || TEMPLATE_ARG=""'.format(lang),
					'rm -Rf %s/*' % config["languages"][lang]["src"],
					'/usr/local/bin/docker-entrypoint.sh generate --enable-post-process-file -i api/openapi-spec/v1.0.yaml $${TEMPLATE_ARG} --additional-properties=packageName=libregraph --git-user-id=owncloud --git-repo-id=%s -g %s -o %s %s' % (config["languages"][lang]["repo-slug"], lang, config["languages"][lang]["src"], config["languages"][lang].get('generator-args', '') ),
					'cp LICENSE %s/LICENSE' % config["languages"][lang]["src"],
				],
			}
			] + validate(lang) + [
			{
				"name": "diff",
				"image": "owncloudci/alpine:latest",
				"commands": [
					"cd %s" % config["languages"][lang]["src"],
					"git diff",
				],
			},
			{
				"name": "publish-%s" % lang,
				"image": "plugins/git-action:1",
				"settings": {
					"actions": [
						"commit",
						"push",
					],
					"message": "%s" % ctx.build.message,
					"branch": "%s" % config["languages"][lang]["branch"],
					"path": "%s" % config["languages"][lang]["src"],
					"author_email": "%s" % ctx.build.author_email,
					"author_name": "%s" % ctx.build.author_name,
					"followtags": True,
					"remote" : "https://github.com/owncloud/%s" % config["languages"][lang]["repo-slug"],
					"netrc_machine": "github.com",
					"netrc_username": {
						"from_secret": "github_username",
					},
					"netrc_password": {
						"from_secret": "github_token",
					},
				},
				"when": {
					"ref": {
						"exclude": [
							"refs/pull/**",
						],
					},
				},
			}],
		'depends_on': [],
		'trigger': {
			'ref': [
				'refs/tags/**',
				'refs/pull/**',
			]
		}
	}

	for branch in config['branches']:
		result['trigger']['ref'].append('refs/heads/%s' % branch)

	pipelines.append(result)

	return pipelines

def validate(lang):
	steps = {
		"cpp-qt-client": [
			{
				"name": "validate-cpp",
				"image": "owncloudci/client",
				"commands": [
					"mkdir build-qt",
					"cd build-qt",
					"cmake -GNinja -S ../%s/client" % config["languages"][lang]["src"],
					"ninja",
					"cd ..",
					"rm -Rf build-qt",
				]
			}
		],
		"go": [
			{
				"name": "go-fmt",
				"image": "owncloudci/golang:1.22",
				"commands": [
					"cd %s" % config["languages"][lang]["src"],
					"gofmt -w .",
				]
			},
			{
				"name": "go-mod",
				"image": "owncloudci/golang:1.22",
				"commands": [
					"cd %s" % config["languages"][lang]["src"],
					"go mod tidy",
				]
			},
			{
				"name": "validate-go",
				"image": "golangci/golangci-lint:latest",
				"commands": [
					"cd %s" % config["languages"][lang]["src"],
					"golangci-lint run -v",
				]
			},
		],
		"php-nextgen": [
			{
				"name": "validate-php",
				"image": "owncloudci/php:8.1",
				"commands": [
					"composer install",
					"vendor/bin/parallel-lint %s" % config["languages"][lang]["src"],
				]
			},
		],
		"typescript-axios": []
	}

	return steps[lang]

def lint(lang):
	if "openapi-generator-image" in config["languages"][lang]:
		# there is a specific openapi-generator-image to use for this language, so validate the yaml spec using that image
		return [
			{
				'name': 'lint',
				'image': config["languages"][lang]["openapi-generator-image"],
				'pull': 'always',
				'commands': [
					'/usr/local/bin/docker-entrypoint.sh validate -i api/openapi-spec/v1.0.yaml',
				],
			}
		]

	return []

def getGeneratorImageVersion(lang):
	if "openapi-generator-image" in config["languages"][lang]:
		return config["languages"][lang]["openapi-generator-image"]
	return config["openapi-generator-image"]
