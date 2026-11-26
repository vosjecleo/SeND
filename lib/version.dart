const deltiecordVersion = '0.9.43';
const deltiecordBuildNumber = '142';
const deltiecordIsPreview = bool.fromEnvironment('SEND_PREVIEW');
const deltiecordDisplayVersion = deltiecordIsPreview
    ? '$deltiecordVersion-preview'
    : deltiecordVersion;
