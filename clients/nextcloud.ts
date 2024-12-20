import puppeteer from "puppeteer";
import { GUI_TYPE_NEXTCLOUD } from "../guiTypes";
import { OwncloudClient } from './owncloud';

export class NextcloudClient extends OwncloudClient {
  FTU_CLOSE_BUTTON: string =  'button.action-item.action-item--single.header-close.icon-close.undefined';
  notificationDoneSelector: string  = 'div.icon-notifications-dark';
  contextMenuSelector: string = 'a.action-menu';
  unshareSelector: string = 'li.action-delete-container';
  loginButton:string = 'input.submit-wrapper__input.primary';
  constructor(params) {
    super(params);
    this.guiType = GUI_TYPE_NEXTCLOUD;
  }

  async createPublicLink() {
    const filesUrl = `https://${this.guiDomain}/index.php/apps/files/?dir=/&openfile=15`; // select nextcloud.png file
    await this.page.goto(filesUrl);

    await this.page.waitForSelector('image.app-icon');
    await this.go('a#sharing');
    const CREATE_PUBLIC_LINK_BUTTON = 'button.new-share-link';
    const elt = await this.page.$(CREATE_PUBLIC_LINK_BUTTON);
    if (elt) {
      await this.page.click(CREATE_PUBLIC_LINK_BUTTON);
    }
    // await this.go('button.action-item__menutoggle');
    // await this.go('li.new-share-link');

    await this.page.waitForSelector('a.sharing-entry__copy');
    return this.page.evaluate("document.querySelector('a.sharing-entry__copy').getAttribute('href')");
  }
  async shareWith(shareWithUser, shareWithHost) {
    const filesUrl = `https://${this.guiDomain}/index.php/apps/files`;
    await this.page.goto(filesUrl);
    // FIXME deal with first-time-use splash screen for Nextcloud Hub
    await this.page.waitForSelector('image.app-icon');
    await this.go('a.action-share');
    // Careful that it types into the top multiselect input and not the bottom one:
    // FIXME: Find a nicer way to do this:
    await new Promise((resolve) => setTimeout(resolve, 1000));

    console.log('Awaiting multiselect');
    await this.page.waitForSelector('div.multiselect');
    await this.page.waitForFunction(
      `document.querySelector("div.multiselect").innerHTML.indexOf("Name, email, or Federated Cloud ID") != -1`
    );
    console.log('multiselect found, placeholder confirmed')
    await this.type('div.multiselect', `${shareWithUser}@${shareWithHost}`);
    console.log('done typing')
    await this.page.waitForFunction(
      `document.querySelector("div.multiselect").innerHTML.indexOf("${shareWithUser}@${shareWithHost}") != -1`
    );
    console.log('typed text has appeared, pressing ArrowDown');
    await this.page.keyboard.press('ArrowDown');
    console.log('Pressing Enter');
    await this.page.keyboard.press('Enter');
    // await this.go('span.option__desc--lineone');
    await this.page.waitForFunction(
      `document.querySelector("body").innerText.includes("${shareWithUser}@${shareWithHost} (remote)")`
    );
  }
  async acceptPublicLink(url, remoteGuiType) {
    await this.page.goto(url);
    await this.go('button.menutoggle');
    await this.go('button#save-external-share');
    await this.page.type('#remote_address', `${this.username}@${this.guiDomain}`);
    await this.page.click('#save-button-confirm');
  }

  async acceptShare() {
    const filesUrl = `https://${this.guiDomain}/index.php/apps/files`;
    await this.page.goto(filesUrl);
    console.log('Clicking to accept share');
    await this.go(".oc-dialog-buttonrow .primary");
    console.log('Clicked to accept share');
  }
}
