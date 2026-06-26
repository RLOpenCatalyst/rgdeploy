import AWS from 'aws-sdk';
import archiver from 'archiver';
import stream from 'stream';

const s3 = new AWS.S3();

export const handler = async (event) => {

    try {
        const reqBody = JSON.parse(event.body);
        const sourceBucket = reqBody.sourceBucket;
        const sourcePrefix = reqBody.sourcePrefix;
        const destinationBucket = reqBody.destinationBucket;
        const destinationPrefix = reqBody.destinationPrefix;
        console.log(`Zipping and uploading files from ${sourcePrefix} to ${destinationPrefix}`);

        // List objects in the source S3 folder
        const listParams = {
            Bucket: sourceBucket,
            Prefix: sourcePrefix
        };
        const contents = [];
        let continuationToken;

        do {
            const page = await s3.listObjectsV2({
                ...listParams,
                ContinuationToken: continuationToken
            }).promise();
            contents.push(...(page.Contents ?? []));
            continuationToken = page.IsTruncated ? page.NextContinuationToken : undefined;
        } while (continuationToken);	    

        if (listedObjects.Contents.length === 0) {
            console.log('No files found in the source folder');
            return { statusCode: 404, body: 'No files found in the source folder' };
        }

        // PassThrough stream and archive setup
        const passThroughStream = new stream.PassThrough();
        const archive = archiver('zip', { zlib: { level: 9 } });

        archive.on('error', (error) => {
            throw new Error(`Archiving error: ${error.message}`);
        });

        archive.pipe(passThroughStream);

        // Start S3 upload process asynchronously
        const uploadParams = {
            Bucket: destinationBucket,
            Key: destinationPrefix,
            Body: passThroughStream,
            ContentType: 'application/zip'
        };
        const uploadPromise = s3.upload(uploadParams).promise();

        // Add files to archive
        for (const obj of contents) {
            const fileKey = obj.Key;
            const fileStream = s3.getObject({ Bucket: sourceBucket, Key: fileKey }).createReadStream();
            const filePath = fileKey.replace(sourcePrefix, '');

            if (!filePath) continue;  // Skip empty paths

            archive.append(fileStream, { name: filePath });
            console.log(`Appended file to archive: ${filePath}`);
        }

        // Finalize the archive to signal completion
        await archive.finalize();

        // Wait for S3 upload to complete
        await uploadPromise;

        console.log('Zip file created and uploaded successfully');

        return {
            statusCode: 201,
            headers: { "Content-Type": "application/json" },
            body: 'Zip file created and uploaded successfully',
            isBase64Encoded: false
        };

    } catch (error) {
        console.error('Error creating or uploading zip file:', error.message);
        return {
            statusCode: 500,
            headers: { "Content-Type": "application/json" },
            body: `Error creating or uploading zip file: ${error.message}`,
            isBase64Encoded: false
        };
    }
};
