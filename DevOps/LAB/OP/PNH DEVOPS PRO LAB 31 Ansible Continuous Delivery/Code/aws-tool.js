// Load the AWS SDK for Node.js
var AWS = require('aws-sdk');
var fs = require('fs');
// var path = require('path');

function initS3(region) {
	// Set the region 
	AWS.config.update({ region: region });

	// Create S3 service object
	var s3 = new AWS.S3({ apiVersion: '2006-03-01' });
	return s3
}

function uploadFileToS3(s3, bucketName, filePath, fileName, mimetype, callback) {
	// call S3 to retrieve upload file to specified bucket
	var uploadParams = { Bucket: bucketName, Key: '', Body: '' };
	// var file = process.argv[3];

	// Configure the file stream and obtain the upload parameters
	var fileStream = fs.createReadStream(filePath);
	fileStream.on('error', function (err) {
		console.log('File Error', err);
	});
	uploadParams.Body = fileStream;
	uploadParams.Key = fileName; // path.basename(filePath);
	uploadParams.ContentType = mimetype

	// call S3 to retrieve upload file to specified bucket
	s3.upload(uploadParams, function (err, data) {
		callback(err, data)
	});
	// s3.upload(uploadParams, function (err, data) {
	// 	if (err) {
	// 		console.log("Error", err);
	// 	} if (data) {
	// 		console.log("Upload Success", data.Location);
	// 	}
	// });
}

module.exports = {
	initS3,
	uploadFileToS3
}