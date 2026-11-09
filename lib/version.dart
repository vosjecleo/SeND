const deltiecordVersion = '0.9.42';
const deltiecordBuildNumber = '139';
const deltiecordIsPreview = bool.fromEnvironment('SEND_PREVIEW');
const deltiecordDisplayVersion = deltiecordIsPreview
    ? '$deltiecordVersion-preview'
    : deltiecordVersion;
