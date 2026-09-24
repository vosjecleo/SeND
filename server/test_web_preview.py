import io
import unittest
from unittest.mock import patch, Mock
import web_preview as preview


class PreviewTests(unittest.TestCase):
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
