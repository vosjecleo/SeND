import io
import unittest
from unittest.mock import patch, Mock
import web_preview as preview


class PreviewTests(unittest.TestCase):
    def test_video_seek_range_matches_request_and_body(self):
        preview.validate_video_range('bytes=16-31', 206, 'bytes 16-31/32', 16)
        preview.validate_video_range('bytes=0-31', 200, None, 32)
        for status, value, length in [(206, 'bytes 0-31/32', 32),
                                      (206, 'bytes 16-31/32', 15),
                                      (206, 'bytes 16-32/32', 17),
                                      (200, None, 32)]:
            with self.subTest(status=status, value=value, length=length):
                with self.assertRaises(ValueError):
                    preview.validate_video_range('bytes=16-31', status, value, length)

    def test_video_handler_rejects_wrong_start_before_reading_or_sending(self):
        response = Mock(status=206)
        response.getheader.side_effect = lambda name, default=None: {
            'Content-Type': 'video/mp4', 'Content-Length': '32',
            'Content-Range': 'bytes 0-31/32'}.get(name, default)
        connection = Mock()
        handler = Mock(path='/api/servers/preview?url=https%3A%2F%2Fvideo.twimg.com%2Fa.mp4&kind=video')
        handler.headers = {'Range': 'bytes=16-31'}
        with patch.object(preview, 'upstream', return_value=(connection, response)):
            preview.handle(handler, lambda *args: True, 'client')
        handler._json.assert_called_once()
        handler.send_response.assert_not_called()
        response.read.assert_not_called()
        connection.close.assert_called_once()

    def test_document_json_is_limited_to_the_fx_status_api(self):
        self.assertTrue(preview.accepts_document(
            'https://api.fxtwitter.com/status/123', 'application/json'))
        for url in ('https://fxtwitter.com/alice/status/123',
                    'https://api.fxtwitter.com/other',
                    'https://other.fxtwitter.com/status/123',
                    'https://imgur.com/status/123'):
            with self.subTest(url=url):
                self.assertFalse(preview.accepts_document(url, 'application/json'))
        self.assertFalse(preview.accepts_document(
            'https://api.fxtwitter.com/status/123', 'application/octet-stream'))
        self.assertTrue(preview.accepts_document(
            'https://fxtwitter.com/alice/status/123', 'text/html'))

    def test_url_allowlist(self):
        for url in ('http://i.imgur.com/a.png', 'https://localhost/a',
                    'https://imgur.com.evil.test/a', 'https://u:p@imgur.com/a',
                    'https://i.imgur.com:8443/a', 'file:///etc/passwd'):
            with self.assertRaises(ValueError):
                preview.validate_url(url)
        self.assertEqual(preview.validate_url('https://i.imgur.com/a.png').hostname, 'i.imgur.com')

    def test_all_dns_answers_must_be_public(self):
        for ip in ('127.0.0.1', '10.0.0.1', '169.254.169.254', '::1',
                   '::ffff:127.0.0.1', '64:ff9b::7f00:1'):
            with patch.object(preview.socket, 'getaddrinfo', return_value=[
                    (2, 1, 6, '', ('8.8.8.8', 443)), (2, 1, 6, '', (ip, 443))]):
                with self.assertRaises(ValueError):
                    preview.public_addresses('i.imgur.com')

    def test_ranges_bounded_and_no_multirange(self):
        self.assertEqual(preview.range_for_request('bytes=0-0'), 'bytes=0-0')
        self.assertEqual(preview.range_for_request('bytes=0-'), 'bytes=0-8388607')
        for value in ('bytes=-999', 'bytes=5-1', 'bytes=0-1,3-4', 'bytes=999999999-'):
            with self.assertRaises(ValueError):
                preview.range_for_request(value)

    def test_response_headers_and_connection_cleanup(self):
        response = Mock(status=200)
        response.getheader.side_effect = lambda name, default=None: {
            'Content-Type': 'image/png', 'Content-Length': '3'}.get(name, default)
        response.read.side_effect = [b'png', b'']
        connection = Mock()
        handler = Mock(path='/api/servers/preview?url=https%3A%2F%2Fi.imgur.com%2Fa.png&kind=image')
        handler.headers = {}
        handler.wfile = io.BytesIO()
        with patch.object(preview, 'upstream', return_value=(connection, response)):
            preview.handle(handler, lambda *args: True, 'client')
        handler.send_response.assert_called_once_with(200)
        handler.send_header.assert_any_call('Cross-Origin-Resource-Policy', 'cross-origin')
        self.assertEqual(handler.wfile.getvalue(), b'png')
        connection.close.assert_called_once()

    def test_html_cannot_be_served_as_media(self):
        response = Mock(status=200)
        response.getheader.side_effect = lambda name, default=None: 'text/html' if name == 'Content-Type' else default
        connection = Mock()
        handler = Mock(path='/api/servers/preview?url=https%3A%2F%2Fi.imgur.com%2Fa&kind=image')
        handler.headers = {}
        with patch.object(preview, 'upstream', return_value=(connection, response)):
            preview.handle(handler, lambda *args: True, 'client')
        handler._json.assert_called_once()
        response.read.assert_not_called()
        connection.close.assert_called_once()
