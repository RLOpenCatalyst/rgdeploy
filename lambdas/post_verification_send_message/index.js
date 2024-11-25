exports.handler = async (event) => {
  try {
    // Identify why this function was invoked
    if ("custom:created_by" in event.request.userAttributes) {
      let body = `Your Research Gateway account username is ${event.userName}`;
      sendEmail(event.request.userAttributes.email, body); // Sending email asynchronously
    }
    // Return to Amazon Cognito
    return event;
  } catch (error) {
    console.error("Error:", error);
    // Return to Amazon Cognito with error
    return event;
  }
};

async function sendEmail(to, body) {
  const { SESClient, SendEmailCommand } = require("@aws-sdk/client-ses");
  const { Config } = require("@aws-sdk/config");

  const ses = new SESClient({ region: "us-east-1", credentials: Config.credentials });

  const eParams = {
    Destination: {
      ToAddresses: [to],
    },
    Message: {
      Body: {
        Text: {
          Data: body,
        },
      },
      Subject: {
        Data: "Research Gateway account verification successful",
      },
    },
    // Replace source_email with your SES validated email address
    Source: "mailto:rlc.support@relevancelab.com",
  };

  try {
    const command = new SendEmailCommand(eParams);
    await ses.send(command); // Send email asynchronously
    console.log("Email sent successfully");
  } catch (error) {
    console.error("Error sending email:", error);
  }
}