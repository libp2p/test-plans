const { test, expect } = require('@playwright/test');

const path = require('path');
const fileURL = 'file://' + path.resolve(__dirname, './index.html');


test.beforeEach(async ({page}) => {
  await page.goto(fileURL);
});

test.afterEach(async ({page}) => {
	const disconnectButton = page.getByTestId('disconnectButton');
	await disconnectButton.click();
});


test.describe('Simple RTC DataChannel', () => {
	test('should send a message from pc1 to pc2', async ({ page }) => {
	    	const connectButton = page.getByTestId('connectButton');
		const messageInputBox = page.getByTestId('message');
		const sendButton = page.getByTestId('sendButton');
		const receivedBox = page.getByTestId('receivebox');

		await connectButton.click();
		await messageInputBox.fill('Hello World');
		await sendButton.click();

		await expect(receivedBox).toHaveText('Messages received: Hello World');
	});

});
