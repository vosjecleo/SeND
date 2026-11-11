const deltiecordVersion = '0.9.42';
const deltiecordBuildNumber = '140';
const deltiecordIsPreview = bool.fromEnvironment('SEND_PREVIEW');
const deltiecordDisplayVersion = deltiecordIsPreview
    ? '$deltiecordVersion-preview'
    : deltiecordVersion;
