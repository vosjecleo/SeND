const deltiecordVersion = '0.9.43';
const deltiecordBuildNumber = '141';
const deltiecordIsPreview = bool.fromEnvironment('SEND_PREVIEW');
const deltiecordDisplayVersion = deltiecordIsPreview
    ? '$deltiecordVersion-preview'
    : deltiecordVersion;
