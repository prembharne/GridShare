const testTextBee = async () => {
  const deviceId = '69d1d8728a04bf362bb53c97';
  const apiKey = '30f1453a-bd52-43aa-a9e3-6dce434a2d2a';
  try {
    const response = await fetch(`https://api.textbee.dev/api/v1/gateway/devices/${deviceId}/send-sms`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
      },
      body: JSON.stringify({
        recipients: ['+918529136151'],
        message: 'This uses the key message instead of smsBody',
      }),
    });
    console.log(response.status, await response.text());
  } catch (error) {
    console.error(error);
  }
};
testTextBee();
